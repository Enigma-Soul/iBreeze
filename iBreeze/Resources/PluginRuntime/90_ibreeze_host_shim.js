// iBreeze 插件运行时 · 宿主层垫片（在 Breeze polyfill 之后注入）
//
// 职责：暴露插件可见的 bridge / console 全局对象，并负责 CommonJS bundle 的装载
// 与 fnPath 调用。必须在 99_exports.js 之后执行，否则会被它清空。
(function () {
  "use strict";

  var host = globalThis.__ibreeze;
  var pluginExports = {};

  // Breeze polyfill 的 99_exports.js 会把未注入的能力置空，这里补回我们自己的实现
  globalThis.bridge = {
    call: function (route) {
      return host.hostCall(route, Array.prototype.slice.call(arguments, 1));
    },
    callSync: function (route) {
      return host.hostCallSync(route, Array.prototype.slice.call(arguments, 1));
    },
    gzipCompress: function (input) {
      return host.hostCall("compression.gzip_compress", [host.bytesToBase64(host.toBytes(input))]);
    },
    gzipDecompress: function (input) {
      return host.hostCall("compression.gzip_decompress", [host.bytesToBase64(host.toBytes(input))]);
    }
  };

  function logger(level) {
    return function () {
      var parts = Array.prototype.slice.call(arguments).map(host.describe);
      globalThis.__log_emit(level, parts.join(" "));
    };
  }

  globalThis.console = {
    log: logger("log"),
    info: logger("info"),
    warn: logger("warn"),
    error: logger("error"),
    debug: logger("debug")
  };

  // Breeze 的 00_bootstrap.js 是从 __web 上取 bridge 的，这里同步一份
  if (globalThis.__web) {
    globalThis.__web.bridge = globalThis.bridge;
    globalThis.__web.console = globalThis.console;
  }

  // 宿主调用：载入 CommonJS bundle（插件为单文件产物，不支持运行时 require）
  //
  // 插件源码写的是 `export default { ... }`，Rspack 打包成 CJS 后会挂在
  // `module.exports.default` 上（并带 __esModule），因此这里要把默认导出取出来，
  // 否则按 fnPath 找函数时会得到「插件未实现 xxx」。
  globalThis.__loadBundle = function (code) {
    var module = { exports: {} };
    var wrapper = new Function("module", "exports", "require", code);
    wrapper(module, module.exports, function (name) {
      throw new Error("插件为单文件 bundle，不支持运行时依赖: " + name);
    });

    var exported = module.exports || {};
    if (exported.default && typeof exported.default === "object") {
      exported = exported.default;
    }
    pluginExports = exported;
    // 调试用：宿主侧可以直接看到插件导出了哪些 fnPath
    globalThis.__pluginExports = exported;
  };

  // 宿主调用：执行某个 fnPath，结果通过 __nativeInvokeResolve 异步回传
  globalThis.__invokePlugin = function (fnPath, payloadJson) {
    try {
      var fn = pluginExports[fnPath];
      if (typeof fn !== "function") {
        throw new Error("插件未实现 " + fnPath);
      }
      Promise.resolve(fn(host.parse(payloadJson))).then(
        function (result) {
          __nativeInvokeResolve(true, host.stringify(result));
        },
        function (error) {
          __nativeInvokeResolve(false, host.describe(error));
        }
      );
    } catch (error) {
      __nativeInvokeResolve(false, host.describe(error));
    }
  };
})();
