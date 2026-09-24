// 插件 JS 层的本地验证工具（无需 macOS / Xcode）
//
// 在一个「只有 ECMAScript 内建对象」的干净上下文里注入 iBreeze 的插件运行时
// 脚本，用 Node 侧的桩替换 Swift 宿主函数，从而验证 JS 层本身是否正确。
//
//   node Tools/plugin-js-harness.mjs
//
// 注意：它只能验证 JS 侧（polyfill、垫片、bundle 装载、fnPath 调用链），
// 网络、加密等真原生能力仍要在真机 / 模拟器上验证。

import { readFileSync } from "node:fs";
import { createContext, runInContext } from "node:vm";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const runtimeDir = join(dirname(fileURLToPath(import.meta.url)), "..", "iBreeze", "Resources", "PluginRuntime");

/// 与 PluginJSLayer.swift 保持一致的注入顺序
const INJECTION_ORDER = [
  "10_ibreeze_native_shim",
  "04_runtime_base_polyfills",
  "00_bootstrap",
  "05_structured_clone",
  "06_url",
  "10_headers",
  "20_abort",
  "30_fetch",
  "60_native",
  "63_stack_hook",
  "70_temporal",
  "99_exports",
  "90_ibreeze_host_shim",
];

const cache = new Map();
const config = new Map();

/// 宿主路由桩：与 PluginHostBridge 的行为保持最小一致
function handleRoute(route, args) {
  switch (route) {
    case "cache.get":
    case "cache.get.sync":
      return cache.has(args[0]) ? JSON.parse(cache.get(args[0])) : (args[1] ?? null);
    case "cache.set":
    case "cache.set.sync":
      cache.set(args[0], JSON.stringify(args[1] ?? null));
      return null;
    case "cache.delete":
      cache.delete(args[0]);
      return null;
    case "save_plugin_config":
      config.set(args[0], args[1]);
      return null;
    case "load_plugin_config":
      return JSON.stringify({ ok: config.has(args[0]), value: config.get(args[0]) ?? args[1] ?? "" });
    case "http.request":
      // 本地不做真实网络：模拟连接失败，用于验证 fetch 的错误路径
      return { ok: false, error: "本地桩：不发起真实网络请求" };
    default:
      throw new Error(`宿主未实现路由：${route}`);
  }
}

function createRuntime() {
  const context = createContext({});
  const timers = new Map();
  let nextTimerId = 1;
  let nextCallId = 1;
  const pendingCalls = new Map();

  context.__nativeLog = (level, message) => {
    if (level === "error") console.error(`    [plugin:${level}] ${message}`);
  };

  context.__nativeCall = (id, route, argsJson) => {
    Promise.resolve()
      .then(() => handleRoute(route, JSON.parse(argsJson || "[]")))
      .then(
        (payload) => context.__nativeCallResolve(id, true, JSON.stringify(payload ?? null)),
        (error) => context.__nativeCallResolve(id, false, String(error?.message ?? error))
      );
  };

  context.__nativeCallSync = (route, argsJson) => {
    try {
      return JSON.stringify({ ok: true, payload: JSON.stringify(handleRoute(route, JSON.parse(argsJson || "[]")) ?? null) });
    } catch (error) {
      return JSON.stringify({ ok: false, payload: String(error?.message ?? error) });
    }
  };

  context.__nativeTimerStart = (delayMs, isInterval) => {
    const id = nextTimerId++;
    const fire = () => {
      if (!isInterval) timers.delete(id);
      context.__host_runtime_timer_complete(id, isInterval ? { kind: "interval" } : {});
    };
    const handle = isInterval ? setInterval(fire, delayMs) : setTimeout(fire, delayMs);
    timers.set(id, { handle, isInterval });
    return JSON.stringify({ ok: true, id });
  };

  context.__nativeTimerDrop = (id) => {
    const entry = timers.get(id);
    if (!entry) return;
    (entry.isInterval ? clearInterval : clearTimeout)(entry.handle);
    timers.delete(id);
  };

  for (const name of INJECTION_ORDER) {
    const source = readFileSync(join(runtimeDir, `${name}.js`), "utf8");
    runInContext(source, context, { filename: `${name}.js` });
  }

  return {
    context,
    load(bundle) {
      context.__loadBundle(bundle);
    },
    invoke(fnPath, payload = {}) {
      return new Promise((resolve, reject) => {
        const id = nextCallId++;
        pendingCalls.set(id, { resolve, reject });
        context.__nativeInvokeResolve = (ok, payloadJson) => {
          const entry = pendingCalls.get(id);
          if (!entry) return;
          pendingCalls.delete(id);
          ok ? entry.resolve(payloadJson) : entry.reject(new Error(payloadJson));
        };
        runInContext(`__invokePlugin(${JSON.stringify(fnPath)}, ${JSON.stringify(JSON.stringify(payload))})`, context);
      });
    },
  };
}

const results = [];
function check(name, condition, detail = "") {
  results.push({ name, ok: Boolean(condition), detail });
  console.log(`${condition ? "✔" : "✘"} ${name}${detail && !condition ? ` — ${detail}` : ""}`);
}

const runtimeBundle = `
module.exports = {
  runtimeGlobals() {
    return {
      hasURL: typeof URL === "function",
      hasHeaders: typeof Headers === "function",
      hasFetch: typeof fetch === "function",
      hasResponse: typeof Response === "function",
      hasAbortController: typeof AbortController === "function",
      hasTextEncoder: typeof TextEncoder === "function",
      hasStructuredClone: typeof structuredClone === "function",
      hasFormData: typeof FormData === "function",
      hasBlob: typeof Blob === "function",
      hasBuffer: typeof Buffer === "function",
      hasTemporal: typeof Temporal !== "undefined",
      pathname: new URL("https://example.com/a/b?x=1").pathname,
      query: new URLSearchParams("a=1&b=2").get("b"),
      base64: bytesToBase64(new TextEncoder().encode("hello")),
      decoded: new TextDecoder().decode(bytesFromBase64("aGVsbG8=")),
    };
  },
  async cacheRoundTrip() {
    await bridge.call("cache.set", "k", { page: 7 });
    const value = await bridge.call("cache.get", "k", null);
    return { page: value.page };
  },
  syncRoundTrip() {
    bridge.callSync("cache.set.sync", "s", { value: 42 });
    return bridge.callSync("cache.get.sync", "s", null);
  },
  async timerDelay() {
    const started = Date.now();
    await new Promise((resolve) => setTimeout(resolve, 30));
    return { elapsed: Date.now() - started };
  },
  async fetchUnreachable() {
    try {
      await fetch("http://example.com/x");
      return { failed: false, message: "" };
    } catch (error) {
      return { failed: true, message: String((error && error.message) || error) };
    }
  },
  binary() {
    return new Uint8Array([1, 2, 3, 4]);
  },
  boom() {
    throw new Error("插件内部错误");
  },
};
`;

const startedAt = Date.now();
const runtime = createRuntime();
runtime.load(runtimeBundle);
console.log(`注入 + 装载耗时 ${Date.now() - startedAt}ms（JavaScriptCore 上会更慢）\n`);

const globals = JSON.parse(await runtime.invoke("runtimeGlobals"));
for (const key of ["hasURL", "hasHeaders", "hasFetch", "hasResponse", "hasAbortController", "hasTextEncoder", "hasStructuredClone", "hasFormData", "hasBlob", "hasBuffer", "hasTemporal"]) {
  check(`全局对象 ${key}`, globals[key] === true);
}
check("URL.pathname 解析", globals.pathname === "/a/b", globals.pathname);
check("URLSearchParams 解析", globals.query === "2", String(globals.query));
check("bytesToBase64", globals.base64 === "aGVsbG8=", String(globals.base64));
check("bytesFromBase64", globals.decoded === "hello", String(globals.decoded));

const cacheResult = JSON.parse(await runtime.invoke("cacheRoundTrip"));
check("bridge.call 缓存往返", cacheResult.page === 7, JSON.stringify(cacheResult));

const syncResult = JSON.parse(await runtime.invoke("syncRoundTrip"));
check("bridge.callSync 缓存往返", Number(syncResult.value) === 42, JSON.stringify(syncResult));

const timer = JSON.parse(await runtime.invoke("timerDelay"));
check("定时器真实等待", timer.elapsed >= 25, `elapsed=${timer.elapsed}`);

const fetchResult = JSON.parse(await runtime.invoke("fetchUnreachable"));
check("fetch 错误路径", fetchResult.failed === true, JSON.stringify(fetchResult));

const binary = JSON.parse(await runtime.invoke("binary"));
check("二进制信封", typeof binary.__ibreezeBinary === "string" && atob(binary.__ibreezeBinary).length === 4, JSON.stringify(binary));

let threw = false;
try {
  await runtime.invoke("boom");
} catch {
  threw = true;
}
check("插件抛错可捕获", threw);

let missingThrew = false;
try {
  await runtime.invoke("notImplemented");
} catch {
  missingThrew = true;
}
check("未实现 fnPath 报错", missingThrew);

const failed = results.filter((item) => !item.ok);
console.log(`\n${results.length - failed.length}/${results.length} 项通过`);
process.exit(failed.length === 0 ? 0 : 1);
