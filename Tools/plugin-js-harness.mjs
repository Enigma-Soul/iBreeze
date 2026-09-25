// 插件 JS 层的本地验证工具（无需 macOS / Xcode）
//
// 在与 App 相同的注入链路上跑自检、BreezeHtml 与网络链路断言。
// 运行时实现见 lib/plugin-runtime.mjs（插件矩阵工具也用它）。
//
//   node Tools/plugin-js-harness.mjs                                  # 自检
//   node Tools/plugin-js-harness.mjs <bundle.cjs> <fnPath> '[json]'   # 跑真实插件
//
// 注意：它只能验证 JS 侧（polyfill、垫片、bundle 装载、fnPath 调用链），
// 真原生能力仍要在真机 / 模拟器上验证。

import { readFileSync } from "node:fs";
import { createRuntime } from "./lib/plugin-runtime.mjs";

/// 用法：
///   node Tools/plugin-js-harness.mjs                                 跑 JS 层自检
///   node Tools/plugin-js-harness.mjs <bundle.cjs> <fnPath> [payload] 跑真实插件（走真实网络）
const [bundlePath, fnPath, payloadJSON] = process.argv.slice(2);
const PLUGIN_MODE = Boolean(bundlePath);

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
  async cryptoRoundTrip() {
    return {
      digest: crypto.createHash("sha256").update("hello").digest("hex"),
      hmac: await crypto.hmacSha256("key", "hello"),
      randomLength: crypto.randomBytes(8).length,
      uuidLength: crypto.randomUUID().length,
    };
  },
  boom() {
    throw new Error("插件内部错误");
  },
};
`;

/// 插件模式：装载真实 bundle 并调用指定 fnPath
async function runPlugin() {
  const runtime = createRuntime({ http: "real" });
  const startedAt = Date.now();
  runtime.load(readFileSync(bundlePath, "utf8"));
  console.log(`装载 ${bundlePath} 耗时 ${Date.now() - startedAt}ms`);

  const target = fnPath || "getInfo";
  const startedCall = Date.now();
  try {
    const raw = await runtime.invoke(target, payloadJSON ? JSON.parse(payloadJSON) : {});
    const elapsed = Date.now() - startedCall;
    console.log(`✔ ${target} 返回（${elapsed}ms）：`);
    console.log(raw.length > 4000 ? `${raw.slice(0, 4000)}…（共 ${raw.length} 字节）` : raw);
  } catch (error) {
    console.log(`✘ ${target} 失败：${error.message}`);
    process.exitCode = 1;
  }
}

/// BreezeHtml 自检：用固定的 HTML 覆盖插件常用的 cheerio 子集
const htmlBundle = `
module.exports = {
  parse() {
    const html = [
      '<div id="list">',
      '<table class="itg"><tr class="r1">',
      '<td class="gl1e"><a href="/g/1/x/"><div title="T1"></div></a></td>',
      '<td class="gl2e">120 pages</td>',
      '</tr><tr class="r2">',
      '<td class="gl1e"><a href="/g/2/y/"><div title="T2"></div></a></td>',
      '<td class="gl2e">80 pages</td>',
      '</tr></table></div>'
    ].join('');
    const $ = BreezeHtml.load(html);
    let eachCount = 0;
    $("td").each(() => { eachCount += 1; });
    return {
      attr: $("a div").first().attr("title"),
      href: $("a").attr("href"),
      text: $("td").eq(1).text(),
      closestText: $("a").first().closest("tr").find(".gl2e").text(),
      count: $("td").length,
      mapped: $("td").map((i, el) => $(el).attr("class")).get().join("|"),
      filtered: $("td").filter(".gl1e").length,
      hasAnchor: $("td").has("a").length,
      nextText: $("td").first().next().text(),
      parentIsTable: $("tr").parent().is("table"),
      childrenCount: $("table").children().length,
      sliced: $("td").slice(0, 2).length,
      lastText: $("td").last().text(),
      toArrayCount: $("td").toArray().length,
      indexValue: $("td").eq(1).index(),
      siblingCount: $("tr").first().siblings().length,
      eachCount: eachCount,
      htmlHead: $("table").html().slice(0, 8),
      innerText: $("#list table tr.r2 td a div").text() === "" ? "empty" : "filled"
    };
  }
};
`;

async function runHtmlChecks() {
  const runtime = createRuntime();
  runtime.load(htmlBundle);
  const result = JSON.parse(await runtime.invoke("parse"));

  check("BreezeHtml: attr", result.attr === "T1", String(result.attr));
  check("BreezeHtml: text", result.text === "120 pages", String(result.text));
  check("BreezeHtml: closest + find", result.closestText === "120 pages", String(result.closestText));
  check("BreezeHtml: 选择器计数", result.count === 4, String(result.count));
  check("BreezeHtml: map/get", result.mapped === "gl1e|gl2e|gl1e|gl2e", String(result.mapped));
  check("BreezeHtml: filter", result.filtered === 2, String(result.filtered));
  check("BreezeHtml: has", result.hasAnchor === 2, String(result.hasAnchor));
  check("BreezeHtml: next", result.nextText === "120 pages", String(result.nextText));
  check("BreezeHtml: parent + is", result.parentIsTable === true, String(result.parentIsTable));
  check("BreezeHtml: children", result.childrenCount === 2, String(result.childrenCount));
  check("BreezeHtml: slice", result.sliced === 2, String(result.sliced));
  check("BreezeHtml: last", result.lastText === "80 pages", String(result.lastText));
  check("BreezeHtml: toArray", result.toArrayCount === 4, String(result.toArrayCount));
  check("BreezeHtml: index", result.indexValue === 1, String(result.indexValue));
  check("BreezeHtml: siblings", result.siblingCount === 1, String(result.siblingCount));
  check("BreezeHtml: each", result.eachCount === 4, String(result.eachCount));
  check("BreezeHtml: html", result.htmlHead === "<tr clas", String(result.htmlHead));
}

/// 网络链路自检：本地起一个 HTTP 服务，用自己写的插件跑完整的
/// 「fetch → Response 读取 → BreezeHtml 解析」流程（不涉及任何第三方代码）
const networkBundle = `
module.exports = {
  async parseHomepage({ url }) {
    const res = await fetch(url);
    const html = await res.text();
    const $ = BreezeHtml.load(html);
    return {
      status: res.status,
      ok: res.ok,
      length: html.length,
      items: $("td.gl1e a").map((i, el) => ({
        href: $(el).attr("href"),
        title: $(el).find("div").attr("title")
      })).get(),
      pages: $("td.gl2e").first().text().trim()
    };
  },
  async parseBinary({ url }) {
    const res = await fetch(url, { headers: { "x-rquickjs-host-offload-binary-v1": "1" } });
    const buffer = await res.arrayBuffer();
    return { byteLength: buffer.byteLength, head: Array.from(new Uint8Array(buffer).slice(0, 4)) };
  }
};
`;

const HOMEPAGE = `<!DOCTYPE html><html><head><title>Gallery</title></head><body>
<table class="itg">
<tr><td class="gl1e"><a href="/g/1/aaa/"><div title="Alpha"></div></a></td><td class="gl2e">120 pages</td></tr>
<tr><td class="gl1e"><a href="/g/2/bbb/"><div title="Beta"></div></a></td><td class="gl2e">80 pages</td></tr>
</table></body></html>`;

async function runNetworkChecks() {
  const { createServer } = await import("node:http");
  const server = createServer((request, response) => {
    if (request.url === "/image") {
      response.writeHead(200, { "content-type": "image/png" });
      response.end(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]));
      return;
    }
    response.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    response.end(HOMEPAGE);
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${server.address().port}`;

  const runtime = createRuntime({ http: "local" });
  runtime.load(networkBundle);

  try {
    const page = JSON.parse(await runtime.invoke("parseHomepage", { url: `${base}/` }));
    check("网络: 状态码", page.status === 200, String(page.status));
    check("网络: 正文长度", page.length > 100, String(page.length));
    check("网络: 解析出条目", page.items.length === 2, JSON.stringify(page.items));
    check("网络: 条目内容", page.items[0]?.title === "Alpha" && page.items[0]?.href === "/g/1/aaa/", JSON.stringify(page.items[0]));
    check("网络: 文本读取", page.pages === "120 pages", String(page.pages));

    const binary = JSON.parse(await runtime.invoke("parseBinary", { url: `${base}/image` }));
    check("网络: 二进制读取", binary.byteLength === 6, String(binary.byteLength));
    check("网络: 二进制内容", JSON.stringify(binary.head) === "[137,80,78,71]", JSON.stringify(binary.head));
  } catch (error) {
    check("网络链路", false, error.message);
  } finally {
    server.close();
  }

  const failed = results.filter((item) => !item.ok);
  console.log(`\n${results.length - failed.length}/${results.length} 项通过`);
  process.exit(failed.length === 0 ? 0 : 1);
}

async function runChecks() {
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

const crypto = JSON.parse(await runtime.invoke("cryptoRoundTrip"));
check(
  "SHA-256（同步钩子）",
  crypto.digest === "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
  String(crypto.digest)
);
check(
  "HMAC-SHA256（异步路由）",
  crypto.hmac === "9307b3b915efb5171ff14d8cb55fbcc798c6c0ef1456d66ded1a6aa723a58b7b",
  JSON.stringify(crypto.hmac)
);
check("randomBytes", crypto.randomLength === 8, String(crypto.randomLength));
check("randomUUID", crypto.uuidLength === 36, String(crypto.uuidLength));

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

await runHtmlChecks();
await runNetworkChecks();
}

if (PLUGIN_MODE) {
  await runPlugin();
} else {
  await runChecks();
}
