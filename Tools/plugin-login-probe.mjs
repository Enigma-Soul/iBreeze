// 登录链路探针：先看插件导出了哪些登录相关方法，再确认未授权错误长什么样。
//
//   node Tools/plugin-login-probe.mjs bika
//
// 只读：不发登录请求，避免把账号密码写进日志。

import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRuntime } from "./lib/plugin-runtime.mjs";

const CACHE_DIR = join(dirname(fileURLToPath(import.meta.url)), ".cache");
const [, , targetName = "bika"] = process.argv;
const bundlePath = join(CACHE_DIR, `${targetName}.bundle.cjs`);

if (!existsSync(bundlePath)) {
  console.error(`没有 ${bundlePath}，先用 plugin-image-probe.mjs ${targetName} 拉一次`);
  process.exit(1);
}

const LOGIN_EXPORTS = [
  "init",
  "getLoginBundle",
  "loginWithPassword",
  "getUserInfoBundle",
  "getCapabilitiesBundle",
  "getSettingsBundle",
  "clearPluginSession",
  "logout",
  "signOut",
];

const runtime = createRuntime({ http: "real" });
runtime.load(readFileSync(bundlePath, "utf8"));

const exports = runtime.context.__pluginExports ?? {};
console.log("登录相关导出：");
for (const name of LOGIN_EXPORTS) {
  console.log(`  ${typeof exports[name] === "function" ? "✔" : "✘"} ${name}`);
}

const info = JSON.parse(await runtime.invoke("getInfo"));
console.log(`\n${info.name} v${info.version} uuid=${info.uuid}`);

if (typeof exports.init === "function") {
  try {
    await runtime.invoke("init", {});
    console.log("init ok");
  } catch (error) {
    console.log("init 失败：", String(error.message).slice(0, 200));
  }
}

if (typeof exports.getLoginBundle === "function") {
  const bundle = JSON.parse(await runtime.invoke("getLoginBundle", {}));
  const scheme = bundle.scheme ?? bundle;
  console.log("\n登录表单：", JSON.stringify(scheme, null, 2).slice(0, 900));
  console.log("预填键：", Object.keys(bundle.data ?? {}));
}

// 未带凭据调一个受保护接口，看抛出来的到底是什么形状
for (const fnPath of ["getHomeData", "getReadSnapshot"]) {
  if (typeof exports[fnPath] !== "function") continue;
  try {
    const raw = await runtime.invoke(fnPath, { comicId: "1", chapterId: "1" });
    console.log(`\n${fnPath} 未报错，返回前 200 字符：${raw.slice(0, 200)}`);
  } catch (error) {
    const message = String(error.message);
    console.log(`\n${fnPath} 抛错，前 260 字符：\n${message.slice(0, 260)}`);
    const brace = message.indexOf("{");
    if (brace >= 0) {
      const slice = message.slice(brace, message.lastIndexOf("}") + 1);
      try {
        console.log("括号内是合法 JSON：", JSON.stringify(JSON.parse(slice)).slice(0, 300));
      } catch (parseError) {
        console.log("按 JSON 解析失败：", parseError.message);
      }
    }
  }
  break;
}
