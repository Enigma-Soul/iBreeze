// 生成 App 图标（1024×1024 PNG），无需任何第三方依赖。
//
//   node Tools/generate-app-icon.mjs
//
// 输出到 iBreeze/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png。
// 画法：2 倍超采样后降采样，得到平滑边缘；图案是渐变底 + 一本翻开的书。

import { deflateSync } from "node:zlib";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const SIZE = 1024;
const SCALE = 2; // 超采样倍数
const CANVAS = SIZE * SCALE;

// ---------- 画布 ----------

const pixels = new Uint8ClampedArray(CANVAS * CANVAS * 4);

function blend(x, y, [r, g, b], alpha) {
  if (alpha <= 0 || x < 0 || y < 0 || x >= CANVAS || y >= CANVAS) return;
  const index = (y * CANVAS + x) * 4;
  const a = Math.min(1, alpha);
  pixels[index] = pixels[index] * (1 - a) + r * a;
  pixels[index + 1] = pixels[index + 1] * (1 - a) + g * a;
  pixels[index + 2] = pixels[index + 2] * (1 - a) + b * a;
  pixels[index + 3] = Math.max(pixels[index + 3], Math.round(a * 255));
}

/// 圆角矩形：覆盖式填充（不做颜色混合时 alpha 传 1）
function fillRoundedRect(x0, y0, width, height, radius, color, alpha = 1) {
  for (let y = Math.floor(y0); y < y0 + height; y += 1) {
    for (let x = Math.floor(x0); x < x0 + width; x += 1) {
      const dx = Math.max(x0 + radius - x, x - (x0 + width - radius - 1), 0);
      const dy = Math.max(y0 + radius - y, y - (y0 + height - radius - 1), 0);
      if (dx * dx + dy * dy <= radius * radius) {
        if (alpha >= 1) {
          const index = (y * CANVAS + x) * 4;
          pixels[index] = color[0];
          pixels[index + 1] = color[1];
          pixels[index + 2] = color[2];
          pixels[index + 3] = 255;
        } else {
          blend(x, y, color, alpha);
        }
      }
    }
  }
}

// ---------- 图案 ----------

const s = (value) => Math.round(value * SCALE);

// 背景渐变：左上靛蓝 → 右下品红
for (let y = 0; y < CANVAS; y += 1) {
  for (let x = 0; x < CANVAS; x += 1) {
    const t = (x / CANVAS) * 0.45 + (y / CANVAS) * 0.55;
    const index = (y * CANVAS + x) * 4;
    pixels[index] = Math.round(95 + (255 - 95) * t);
    pixels[index + 1] = Math.round(102 + (106 - 102) * t);
    pixels[index + 2] = Math.round(230 + (156 - 230) * t);
    pixels[index + 3] = 255;
  }
}

// 书：左右两页 + 书脊（主体约占画布 72% 宽）
const bookTop = s(248);
const pageWidth = s(374);
const pageHeight = s(528);
const pageRadius = s(34);
const cream = [255, 253, 250];
const shade = [226, 224, 244];
const spine = [72, 70, 160];

fillRoundedRect(s(138), bookTop, pageWidth, pageHeight, pageRadius, cream);
fillRoundedRect(s(512), bookTop, pageWidth, pageHeight, pageRadius, cream);
// 书脊阴影，营造翻开的感觉
fillRoundedRect(s(494), bookTop + s(8), s(104), pageHeight - s(16), s(12), shade);
fillRoundedRect(s(500), bookTop, s(26), pageHeight, 0, spine);
// 书页上的行线
for (let line = 0; line < 6; line += 1) {
  const y = bookTop + s(78) + line * s(74);
  fillRoundedRect(s(186), y, pageWidth - s(96), s(16), s(8), shade);
  fillRoundedRect(s(560), y, pageWidth - s(96), s(16), s(8), shade);
}

// ---------- 降采样 ----------

const out = Buffer.alloc(SIZE * SIZE * 4);
for (let y = 0; y < SIZE; y += 1) {
  for (let x = 0; x < SIZE; x += 1) {
    let r = 0, g = 0, b = 0, a = 0;
    for (let dy = 0; dy < SCALE; dy += 1) {
      for (let dx = 0; dx < SCALE; dx += 1) {
        const index = ((y * SCALE + dy) * CANVAS + x * SCALE + dx) * 4;
        r += pixels[index];
        g += pixels[index + 1];
        b += pixels[index + 2];
        a += pixels[index + 3];
      }
    }
    const count = SCALE * SCALE;
    const index = (y * SIZE + x) * 4;
    out[index] = Math.round(r / count);
    out[index + 1] = Math.round(g / count);
    out[index + 2] = Math.round(b / count);
    out[index + 3] = Math.round(a / count);
  }
}

// ---------- PNG 编码 ----------

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buffer) {
  let c = 0xffffffff;
  for (const byte of buffer) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const typeAndData = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(typeAndData));
  return Buffer.concat([length, typeAndData, crc]);
}

const raw = Buffer.alloc(SIZE * (SIZE * 4 + 1));
for (let y = 0; y < SIZE; y += 1) {
  raw[y * (SIZE * 4 + 1)] = 0; // filter: none
  out.copy(raw, y * (SIZE * 4 + 1) + 1, y * SIZE * 4, (y + 1) * SIZE * 4);
}

const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(SIZE, 0);
ihdr.writeUInt32BE(SIZE, 4);
ihdr[8] = 8; // bit depth
ihdr[9] = 6; // RGBA
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk("IHDR", ihdr),
  chunk("IDAT", deflateSync(raw, { level: 9 })),
  chunk("IEND", Buffer.alloc(0)),
]);

const target = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "iBreeze",
  "Resources",
  "Assets.xcassets",
  "AppIcon.appiconset",
  "icon-1024.png"
);
writeFileSync(target, png);
console.log(`已生成 ${target}（${(png.length / 1024).toFixed(1)} KB）`);
