// 插件矩阵：批量检查插件列表里每个插件能否被 iBreeze 正常安装与调用。
//
//   node Tools/plugin-matrix.mjs [plugins_data.json 路径] [--net]
//
// 默认只跑「下载 + 装载 + getInfo」——这正是 App 安装时走的那条路。
// 加 --net 会额外调用插件的第一个列表入口，检查真实取数（较慢、依赖网络）。

import { readFileSync } from "node:fs";
import { createRuntime } from "./lib/plugin-runtime.mjs";

const DEFAULT_LIST = new URL("../../iBreeze-refs/Breeze-plugin-list/plugins_data.json", import.meta.url);
const args = process.argv.slice(2);
const listPath = args.find((item) => !item.startsWith("--")) ?? DEFAULT_LIST;
const withNetwork = args.includes("--net");

/// 与 PluginInstaller.cdnMirrors / gitHubProxies 一致
const MIRRORS = [
  "https://cdn.jsdmirror.com/",
  "https://cdn.jsdmirror.cn/",
  "https://cdn.jsdelivr.net/",
  "https://jsd.onmicrosoft.cn/",
  "https://www.webcache.cn/",
];
const GH_PROXIES = ["https://ghfast.top/", "https://gh-proxy.com/"];

const plugins = JSON.parse(readFileSync(listPath, "utf8"));
console.log(`共 ${plugins.length} 个插件，网络取数：${withNetwork ? "开" : "关"}\n`);

async function fetchText(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const text = await response.text();
  if (!text.trim()) throw new Error("内容为空");
  return text;
}

/// 与 PluginInstaller 的策略一致：npm 多镜像优先，失败再回退 GitHub Release
async function downloadBundle(manifest) {
  const npmName = manifest.npmName?.trim();
  const errors = [];

  if (npmName) {
    for (const mirror of MIRRORS) {
      const url = `${mirror}npm/${npmName}@latest/dist/${npmName}.bundle.cjs`;
      try {
        return { bundle: await fetchText(url), source: url };
      } catch (error) {
        errors.push(`npm ${error.message}`);
      }
    }
  }

  const updateUrl = manifest.updateUrl?.trim();
  if (updateUrl) {
    let release = null;
    for (const candidate of [updateUrl, ...GH_PROXIES.map((proxy) => proxy + updateUrl)]) {
      try {
        release = JSON.parse(await fetchText(candidate));
        break;
      } catch (error) {
        errors.push(`updateUrl ${error.message}`);
      }
    }

    if (release) {
      const asset = (release.assets ?? []).find((item) => item.name?.endsWith(".cjs"));
      if (!asset) {
        errors.push("Release 里没有 .cjs 资产");
      } else {
        const repoPath = /repos\/([^/]+)\/([^/]+)/.exec(updateUrl);
        const candidates = [
          asset.browser_download_url,
          ...GH_PROXIES.map((proxy) => proxy + asset.browser_download_url),
        ];
        if (repoPath && release.tag_name) {
          for (const mirror of MIRRORS) {
            candidates.push(`${mirror}gh/${repoPath[1]}/${repoPath[2]}@${release.tag_name}/${asset.name}`);
          }
        }
        for (const candidate of candidates) {
          try {
            return { bundle: await fetchText(candidate), source: candidate };
          } catch (error) {
            errors.push(`release ${error.message}`);
          }
        }
      }
    }
  }

  return { error: errors.length ? errors.join("；") : "既没有 npmName 也没有可用的 updateUrl" };
}

const failures = [];

for (const entry of plugins) {
  const manifest = entry.manifest ?? {};
  const label = `${manifest.name ?? entry.repo}`.padEnd(18);
  const downloaded = await downloadBundle(manifest);

  if (downloaded.error) {
    failures.push({ name: label, reason: downloaded.error });
    console.log(`✘ ${label} ${downloaded.error}`);
    continue;
  }

  let runtime;
  try {
    runtime = createRuntime({ http: withNetwork ? "real" : "stub" });
    runtime.load(downloaded.bundle);
  } catch (error) {
    failures.push({ name: label, reason: `装载失败：${error.message}` });
    console.log(`✘ ${label} 装载失败：${error.message}`);
    continue;
  }

  try {
    const info = JSON.parse(await runtime.invoke("getInfo"));
    const problems = [];
    if (!info.uuid) problems.push("getInfo 未返回 uuid");
    if (info.uuid && manifest.uuid && info.uuid !== manifest.uuid) {
      problems.push(`uuid 不一致（清单 ${manifest.uuid} / 实际 ${info.uuid}）`);
    }

    if (problems.length > 0) {
      failures.push({ name: label, reason: problems.join("；") });
      console.log(`✘ ${label} ${problems.join("；")}`);
      continue;
    }

    // 没有浏览入口不算失败：这类插件只能靠搜索，App 里会引导到「搜索该插件」
    const entries = info.function?.length ?? 0;
    let extra = entries === 0 ? " · 仅搜索" : "";
    if (withNetwork) {
      const scene = info.function?.find((item) => item.action?.type === "openComicList")?.action?.payload?.scene;
      if (scene) {
        const started = Date.now();
        try {
          const list = await runtime.invoke(scene.body.request.fnPath, {
            page: 1,
            ...(scene.body.request.core ?? {}),
            extern: scene.body.request.extern ?? {},
          });
          const items = JSON.parse(list).items ?? JSON.parse(list).data?.items ?? [];
          extra = ` · 列表 ${items.length} 项 / ${Date.now() - started}ms`;
          if (items.length === 0) extra += "（空）";
        } catch (error) {
          extra = ` · 列表取数失败：${error.message.slice(0, 80)}`;
          failures.push({ name: label, reason: `取数失败：${error.message.slice(0, 120)}` });
        }
      }
    }

    console.log(`✔ ${label} v${info.version ?? "?"} · ${entries} 个入口${extra}`);
  } catch (error) {
    failures.push({ name: label, reason: `getInfo 失败：${error.message}` });
    console.log(`✘ ${label} getInfo 失败：${error.message}`);
  }
}

console.log(`\n${plugins.length - failures.length}/${plugins.length} 个插件可用`);
if (failures.length > 0) {
  console.log("\n失败清单：");
  for (const item of failures) console.log(`  ${item.name} ${item.reason}`);
  process.exitCode = 1;
}
