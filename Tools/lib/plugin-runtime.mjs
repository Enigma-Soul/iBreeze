// 插件 JS 运行时的本地验证内核。
//
// 在一个「只有 ECMAScript 内建对象」的干净上下文里，按 App 相同的顺序注入 JS 层，
// 用 Node 侧的桩替换 Swift 宿主函数。自检工具与插件矩阵工具共用这份实现，
// 保证「本地验证通过」与「App 里能跑」是同一套逻辑。

import { readFileSync } from "node:fs";
import { createContext, runInContext } from "node:vm";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  pbkdf2Sync,
  randomBytes,
  randomUUID,
  timingSafeEqual,
} from "node:crypto";

/// 与 PluginJSLayer.swift 保持一致
export const INJECTION_ORDER = [
  "10_ibreeze_native_shim",
  "20_ibreeze_html",
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

// Node 的 fetch 默认不读 HTTP_PROXY，而 NODE_USE_ENV_PROXY 只在启动时生效。
// 检测到本机配置了代理就带上它重启一次，这样在 Clash 之类环境下直接跑即可。
if (!process.env.NODE_USE_ENV_PROXY && !process.env.HARNESS_REEXEC
  && (process.env.HTTP_PROXY || process.env.HTTPS_PROXY)) {
  const result = spawnSync(process.execPath, process.argv.slice(1), {
    stdio: "inherit",
    env: { ...process.env, NODE_USE_ENV_PROXY: "1", HARNESS_REEXEC: "1" },
  });
  process.exit(result.status ?? 1);
}

const runtimeDir = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "iBreeze", "Resources", "PluginRuntime");

const bytes = (value) => Buffer.from(value ?? []);
const digestPayload = (buffer) => ({ hex: buffer.toString("hex"), base64: buffer.toString("base64") });

/// 真实网络请求
async function httpRequest(args) {
  const [, method, url, headers, bodyText, bodyBase64] = args;
  let response;
  try {
    response = await fetch(url, {
      method: method || "GET",
      headers: headers ?? {},
      body: bodyBase64 ? Buffer.from(bodyBase64, "base64") : bodyText ?? undefined,
    });
  } catch (error) {
    if (!process.env.NODE_USE_ENV_PROXY) {
      throw new Error(`${error.message}（本机连不上目标站点时，可用 NODE_USE_ENV_PROXY=1 让 Node 走 HTTP_PROXY）`);
    }
    throw error;
  }

  const buffer = Buffer.from(await response.arrayBuffer());
  return {
    ok: true,
    status: response.status,
    statusText: response.statusText,
    headers: Object.fromEntries(response.headers),
    url: response.url,
    bodyBase64: buffer.toString("base64"),
  };
}

/// 宿主路由桩：与 PluginHostBridge 的行为保持最小一致
function createRouteHandler({ http, stubFile }) {
  const cache = new Map();
  const config = new Map();

  return function handleRoute(route, args) {
    if (process.env.HARNESS_DEBUG) console.error("route:", route, JSON.stringify(args));

    if (route === "http.request") {
      if (stubFile) {
        const body = readFileSync(stubFile);
        return {
          ok: true,
          status: 200,
          statusText: "OK",
          headers: { "content-type": "text/html; charset=utf-8" },
          url: args[2],
          bodyBase64: body.toString("base64"),
        };
      }
      if (http === "real") return httpRequest(args);

      const target = String(args[2] ?? "");
      const isLocal = /^https?:\/\/(127\.0\.0\.1|localhost)(:|\/|$)/.test(target);
      if (http === "local" && isLocal) return httpRequest(args);
      return { ok: false, error: "本地桩：不发起真实网络请求" };
    }

    switch (route) {
      // 加密：与 PluginCryptoRoutes 的约定一致
      case "crypto.md5":
      case "crypto.sha1":
      case "crypto.sha256":
      case "crypto.sha512":
        return createHash(route.slice("crypto.".length)).update(bytes(args[0])).digest("hex");
      case "crypto.hmac_sha1":
      case "crypto.hmac_sha256":
      case "crypto.hmac_sha512":
        return createHmac(route.slice("crypto.hmac_".length), bytes(args[0])).update(bytes(args[1])).digest("hex");
      case "crypto.md5_hex":
      case "crypto.sha1_hex":
      case "crypto.sha256_hex":
      case "crypto.sha512_hex":
        return createHash(route.slice("crypto.".length, -4)).update(String(args[0]), "utf8").digest("hex");
      case "crypto.sha1_bytes":
      case "crypto.sha256_bytes":
      case "crypto.sha512_bytes":
        return digestPayload(createHash(route.slice("crypto.".length, -6)).update(bytes(args[0])).digest());
      case "crypto.hmac_sha1_bytes":
      case "crypto.hmac_sha256_bytes":
      case "crypto.hmac_sha512_bytes":
        return digestPayload(
          createHmac(route.slice("crypto.hmac_".length, -6), bytes(args[0])).update(bytes(args[1])).digest()
        );
      case "crypto.pbkdf2_sha256_bytes":
        return digestPayload(pbkdf2Sync(bytes(args[0]), bytes(args[1]), args[2], args[3], "sha256"));
      case "crypto.aes_cbc_pkcs7_encrypt_bytes":
      case "crypto.aes_cbc_pkcs7_decrypt_bytes": {
        const machine = (route.endsWith("encrypt_bytes") ? createCipheriv : createDecipheriv)(
          "aes-256-cbc", bytes(args[1]), bytes(args[2])
        );
        return digestPayload(Buffer.concat([machine.update(bytes(args[0])), machine.final()]));
      }
      case "crypto.aes_gcm_encrypt_bytes":
      case "crypto.aes_gcm_decrypt_bytes": {
        const encrypt = route.endsWith("encrypt_bytes");
        const aad = args[3] === null || args[3] === undefined ? null : bytes(args[3]);
        const machine = (encrypt ? createCipheriv : createDecipheriv)("aes-256-gcm", bytes(args[1]), bytes(args[2]));
        if (aad) machine.setAAD(aad);
        if (encrypt) {
          return digestPayload(Buffer.concat([machine.update(bytes(args[0])), machine.final(), machine.getAuthTag()]));
        }
        machine.setAuthTag(bytes(args[0]).subarray(-16));
        return digestPayload(Buffer.concat([machine.update(bytes(args[0]).subarray(0, -16)), machine.final()]));
      }
      case "crypto.timing_safe_equal_bytes": {
        const [left, right] = [bytes(args[0]), bytes(args[1])];
        return { equal: left.length === right.length && timingSafeEqual(left, right) };
      }
      case "crypto.random_bytes":
        return Array.from(randomBytes(Number(args[0])));
      case "crypto.random_uuid_v4":
        return { uuid: randomUUID() };

      case "cache.get":
      case "cache.get.sync":
        return cache.has(args[0]) ? JSON.parse(cache.get(args[0])) : (args[1] ?? null);
      case "cache.set":
      case "cache.set.sync":
        cache.set(args[0], JSON.stringify(args[1] ?? null));
        return null;
      case "cache.set_if_absent": {
        if (cache.has(args[0])) return false;
        cache.set(args[0], JSON.stringify(args[1] ?? null));
        return true;
      }
      case "cache.compare_and_set": {
        const expected = JSON.stringify(args[1] ?? null);
        if (cache.get(args[0]) !== expected) return false;
        cache.set(args[0], JSON.stringify(args[2] ?? null));
        return true;
      }
      case "cache.delete":
        cache.delete(args[0]);
        return null;
      case "save_plugin_config":
        config.set(args[0], args[1]);
        return null;
      case "load_plugin_config":
        return JSON.stringify({ ok: config.has(args[0]), value: config.get(args[0]) ?? args[1] ?? "" });

      case "math.add":
        return Number(args[0] ?? 0) + Number(args[1] ?? 0);
      case "dart.getAppVersion":
        return "0.1.0 (harness)";
      case "dart.getLocaleInfo":
        return JSON.stringify({
          language: "zh",
          locale: "zh-CN",
          systemLocale: "zh-CN",
          timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
          timeZoneIANA: Intl.DateTimeFormat().resolvedOptions().timeZone,
          timezoneOffset: "+08:00",
          timezoneOffsetMinutes: -new Date().getTimezoneOffset(),
          timezoneName: "CST",
        });
      case "flutter.showToast":
        return null;
      case "runtime.gc":
        return null;
      case "runtime.is_task_group_cancelled":
        return false;

      default:
        throw new Error(`宿主未实现路由：${route}`);
    }
  };
}

/// 建一个运行时，可选是否联网
export function createRuntime({ http = "stub", stubFile = process.env.HARNESS_STUB_HTTP ?? null } = {}) {
  const handleRoute = createRouteHandler({ http, stubFile });

  const context = createContext({});
  const timers = new Map();
  let nextTimerId = 1;
  let nextCallId = 1;
  const pendingCalls = new Map();

  context.__nativeLog = (level, message) => {
    if (process.env.HARNESS_VERBOSE_LOG || level === "error") {
      console.error(`    [plugin:${level}] ${message}`);
    }
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
    timers.set(id, { handle: isInterval ? setInterval(fire, delayMs) : setTimeout(fire, delayMs), isInterval });
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
