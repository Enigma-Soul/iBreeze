// 把一张图片转换成 iOS 可用的 App 图标（1024×1024 PNG，无 alpha 通道）。
//
//   node Tools/prepare-app-icon.mjs <源图片路径>
//
// 只用 Node 内置能力完成解码、缩放与编码，不依赖任何第三方库。
// iOS 要求图标不能带 alpha 通道，因此这里会把透明像素合成到白底。

import { deflateSync, inflateSync } from "node:zlib";
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const SIZE = 1024;

// ---------- PNG 解码 ----------

function decodePNG(buffer) {
  const signature = buffer.slice(0, 8).toString("hex");
  if (signature !== "89504e470d0a1a0a") throw new Error("不是 PNG 文件");

  let offset = 8;
  let header = null;
  const dataChunks = [];

  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.slice(offset + 4, offset + 8).toString("ascii");
    const data = buffer.slice(offset + 8, offset + 8 + length);

    if (type === "IHDR") {
      header = {
        width: data.readUInt32BE(0),
        height: data.readUInt32BE(4),
        depth: data[8],
        colorType: data[9],
        interlace: data[12],
      };
    } else if (type === "IDAT") {
      dataChunks.push(data);
    } else if (type === "IEND") {
      break;
    }
    offset += length + 12;
  }

  if (!header) throw new Error("缺少 IHDR");
  if (header.depth !== 8) throw new Error(`暂不支持位深 ${header.depth}`);
  if (header.interlace !== 0) throw new Error("暂不支持隔行扫描");
  if (header.colorType !== 2 && header.colorType !== 6) {
    throw new Error(`暂不支持颜色类型 ${header.colorType}（只支持 RGB / RGBA）`);
  }

  const channels = header.colorType === 6 ? 4 : 3;
  const stride = header.width * channels;
  const raw = inflateSync(Buffer.concat(dataChunks));

  const pixels = Buffer.alloc(header.height * stride);
  for (let y = 0; y < header.height; y += 1) {
    const filter = raw[y * (stride + 1)];
    const line = raw.slice(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const target = pixels.slice(y * stride, (y + 1) * stride);
    const previous = y > 0 ? pixels.slice((y - 1) * stride, y * stride) : null;

    for (let x = 0; x < stride; x += 1) {
      const left = x >= channels ? target[x - channels] : 0;
      const up = previous ? previous[x] : 0;
      const upLeft = previous && x >= channels ? previous[x - channels] : 0;

      let value;
      switch (filter) {
        case 0: value = line[x]; break;
        case 1: value = line[x] + left; break;
        case 2: value = line[x] + up; break;
        case 3: value = line[x] + ((left + up) >> 1); break;
        case 4: {
          const p = left + up - upLeft;
          const pa = Math.abs(p - left);
          const pb = Math.abs(p - up);
          const pc = Math.abs(p - upLeft);
          value = line[x] + (pa <= pb && pa <= pc ? left : pb <= pc ? up : upLeft);
          break;
        }
        default: throw new Error(`未知的行过滤器 ${filter}`);
      }
      target[x] = value & 0xff;
    }
  }

  return { ...header, channels, pixels, stride };
}

// ---------- 缩放：按比例取平均，顺便把透明像素合成到白底 ----------

function resize({ width, height, channels, pixels, stride }, size) {
  const output = Buffer.alloc(size * size * 3);
  const scaleX = width / size;
  const scaleY = height / size;

  for (let y = 0; y < size; y += 1) {
    const y0 = Math.floor(y * scaleY);
    const y1 = Math.max(y0 + 1, Math.floor((y + 1) * scaleY));

    for (let x = 0; x < size; x += 1) {
      const x0 = Math.floor(x * scaleX);
      const x1 = Math.max(x0 + 1, Math.floor((x + 1) * scaleX));

      let r = 0, g = 0, b = 0, a = 0, count = 0;
      for (let sy = y0; sy < y1; sy += 1) {
        for (let sx = x0; sx < x1; sx += 1) {
          const index = sy * stride + sx * channels;
          const alpha = channels === 4 ? pixels[index + 3] / 255 : 1;
          // 先合成到白底，避免缩放后边缘出现暗边
          r += pixels[index] * alpha + 255 * (1 - alpha);
          g += pixels[index + 1] * alpha + 255 * (1 - alpha);
          b += pixels[index + 2] * alpha + 255 * (1 - alpha);
          a += alpha;
          count += 1;
        }
      }

      output[(y * size + x) * 3] = Math.round(r / count);
      output[(y * size + x) * 3 + 1] = Math.round(g / count);
      output[(y * size + x) * 3 + 2] = Math.round(b / count);
    }
  }

  return output;
}

// ---------- PNG 编码（RGB，无 alpha） ----------

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
  const payload = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(payload));
  return Buffer.concat([length, payload, crc]);
}

function encodePNG(pixels, size) {
  const raw = Buffer.alloc(size * (size * 3 + 1));
  for (let y = 0; y < size; y += 1) {
    raw[y * (size * 3 + 1)] = 0;
    pixels.copy(raw, y * (size * 3 + 1) + 1, y * size * 3, (y + 1) * size * 3);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;
  ihdr[9] = 2; // RGB，无 alpha

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// ---------- 入口 ----------

const source = process.argv[2];
if (!source) {
  console.error("用法：node Tools/prepare-app-icon.mjs <源图片路径>");
  process.exit(1);
}

const decoded = decodePNG(readFileSync(source));
console.log(`源图 ${decoded.width}×${decoded.height}，${decoded.channels === 4 ? "RGBA" : "RGB"}`);

const png = encodePNG(resize(decoded, SIZE), SIZE);
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
