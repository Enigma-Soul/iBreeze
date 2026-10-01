// 取图链路探针：按 App 的真实顺序把一个插件的「列表 → 详情 → 章节 → 图片」跑一遍，
// 每一步都打时间，用来定位「图片下不下来」卡在哪一段。
//
//   node Tools/plugin-image-probe.mjs ehentai [关键词]
//
// 依赖本机代理（HTTP_PROXY / HTTPS_PROXY），运行时内核与 App 共用同一套 JS 层。

import { writeFileSync } from "node:fs";
import { createRuntime } from "./lib/plugin-runtime.mjs";

/// 与 PluginInstaller.cdnMirrors / gitHubProxies 一致
const MIRRORS = [
  "https://cdn.jsdmirror.com/",
  "https://cdn.jsdmirror.cn/",
  "https://cdn.jsdelivr.net/",
  "https://jsd.onmicrosoft.cn/",
  "https://www.webcache.cn/",
];
const GH_PROXIES = ["https://ghfast.top/", "https://gh-proxy.com/"];

const TARGETS = {
  ehentai: {
    npmName: "breeze-plugin-ehentai",
    uuid: "dba2a6cf-c495-4416-accf-c29263ab4016",
    updateUrl: "https://api.github.com/repos/deretame/Breeze-plugin-ehentai/releases/latest",
  },
  bika: {
    npmName: "breeze-plugin-bika-comic",
    uuid: "0a0e5858-a467-4702-994a-79e608a4589d",
    updateUrl: "https://api.github.com/repos/deretame/Breeze-plugin-bikaComic/releases/latest",
  },
  jm: {
    npmName: "breeze-plugin-jm-comic",
    uuid: "bf99008d-010b-4f17-ac7c-61a9b57dc3d9",
    updateUrl: "https://api.github.com/repos/deretame/Breeze-plugin-JmComic/releases/latest",
  },
};

const [, , targetName = "ehentai", keyword = ""] = process.argv;
const target = TARGETS[targetName];
if (!target) throw new Error(`未知目标：${targetName}（可选 ${Object.keys(TARGETS).join(" / ")}）`);

const started = Date.now();
const mark = (label, extra = "") =>
  console.log(`[${String(Date.now() - started).padStart(6)}ms] ${label}${extra ? " " + extra : ""}`);

async function fetchText(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const text = await response.text();
  if (!text.trim()) throw new Error("内容为空");
  return text;
}

async function downloadBundle() {
  const asset = `${target.npmName}.bundle.cjs`;
  const candidates = MIRRORS.map((mirror) => `${mirror}npm/${target.npmName}@latest/dist/${asset}`);

  // npm 镜像常常限流，回退到 GitHub Release（与 PluginInstaller 的策略一致）
  const release = await fetchText(target.updateUrl).then(JSON.parse).catch(() => null);
  const releaseAsset = (release?.assets ?? []).find((item) => item.name === asset);
  if (releaseAsset) {
    candidates.push(releaseAsset.browser_download_url);
    for (const proxy of GH_PROXIES) candidates.push(proxy + releaseAsset.browser_download_url);
  }

  const failures = [];
  for (const url of candidates) {
    try {
      const bundle = await fetchText(url);
      mark("下载插件", url);
      return bundle;
    } catch (error) {
      failures.push(`${new URL(url).host} ${error.message}`);
    }
  }
  throw new Error(`所有下载渠道都失败：\n  ${failures.join("\n  ")}`);
}

function parse(json) {
  return JSON.parse(json);
}

const bundle = await downloadBundle();
const runtime = createRuntime({ http: "real" });
runtime.load(bundle);
mark("装载完成");

const info = parse(await runtime.invoke("getInfo"));
mark("getInfo", `v${info.version}`);

if (typeof info.init === "function" || info.hasInit) {
  /* 插件把 init 暴露在导出上时由 __invokePlugin 直接调 */
}

async function invoke(fnPath, payload = {}) {
  const at = Date.now();
  const raw = await runtime.invoke(fnPath, payload);
  return { raw, elapsed: Date.now() - at };
}

// 1. 找一个能用的列表入口
const entry = (info.function ?? []).find((item) => item.action?.payload?.scene) ?? null;
if (!entry) throw new Error("该插件没有声明任何列表入口");

const scene = entry.action.payload.scene;
const request = scene.body?.request ?? scene.list ?? scene;
mark("使用入口", `${entry.title} → ${request.fnPath}`);

const list = await invoke(request.fnPath, {
  page: 1,
  ...(request.core ?? {}),
  extern: request.extern ?? {},
});
const listBody = parse(list.raw);
const items = listBody.items ?? listBody.data?.items ?? [];
mark("列表", `${items.length} 项 / ${list.elapsed}ms`);
if (items.length === 0) throw new Error("列表为空，无法继续");

const item = items[0];
console.log(`          首项：${item.title ?? item.name ?? "?"} id=${item.id ?? item.comicId ?? "?"}`);

// 2. 详情
const comicId = String(item.id ?? item.comicId ?? "");
const detail = await invoke("getComicDetail", { comicId, extern: item.extern ?? {} });
const detailBody = parse(detail.raw);
const chapters = detailBody.data?.chapters ?? detailBody.chapters ?? [];
mark("详情", `${chapters.length} 章 / ${detail.elapsed}ms`);
if (chapters.length === 0) throw new Error("详情没有章节");

// 3. 阅读快照
const chapter = chapters[0];
const chapterId = String(chapter.id ?? chapter.chapterId ?? "");
const snapshot = await invoke("getReadSnapshot", {
  comicId,
  chapterId,
  extern: chapter.extern ?? {},
});
const snapshotBody = parse(snapshot.raw);
const pages = snapshotBody.data?.chapter?.pages ?? snapshotBody.chapter?.pages ?? [];
mark("章节", `${pages.length} 页 / ${snapshot.elapsed}ms`);
if (pages.length === 0) throw new Error("章节没有页面");

// 4. 逐页取图：前 3 页，记录每页耗时与字节数
for (const [index, page] of pages.slice(0, 3).entries()) {
  const at = Date.now();
  try {
    const raw = await runtime.invoke("fetchImageBytes", {
      url: page.url,
      timeoutMs: 30_000,
      taskGroupKey: "",
      extern: page.extern ?? {},
    });
    const body = parse(raw);
    const bytes = body.__ibreezeBinary ?? body.data ?? null;
    const size = typeof bytes === "string" ? Math.floor((bytes.length * 3) / 4) : 0;
    mark(`取图 #${index + 1}`, `${size} 字节 / ${Date.now() - at}ms url=${String(page.url).slice(0, 70)}`);
    if (index === 0 && typeof bytes === "string") {
      writeFileSync(`probe-${targetName}-1.bin`, Buffer.from(bytes, "base64"));
      mark("已落盘", `probe-${targetName}-1.bin`);
    }
  } catch (error) {
    mark(`取图 #${index + 1} 失败`, `${Date.now() - at}ms ${String(error.message).slice(0, 160)}`);
  }
}

mark("结束");
