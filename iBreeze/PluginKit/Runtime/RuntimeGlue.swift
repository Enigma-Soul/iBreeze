import Foundation

/// 注入到插件运行时的 JS 胶水层。
///
/// 负责把宿主能力包装成 `bridge`、`console` 等全局对象，并把 CommonJS bundle
/// 的导出收集起来，供宿主按 `fnPath` 调用。语义对齐 Breeze 的插件运行时约定。
enum RuntimeGlue {
    static let source = #"""
    (function () {
        "use strict";

        var pending = new Map();
        var sequence = 0;
        var pluginExports = {};

        function describe(error) {
            if (error === null || error === undefined) return "未知错误";
            if (typeof error === "string") return error;
            if (error && error.message) return String(error.message);
            return String(error);
        }

        function stringify(value) {
            if (value === undefined) return "null";
            try {
                return JSON.stringify(value);
            } catch (error) {
                return JSON.stringify({ error: "返回值无法序列化为 JSON: " + describe(error) });
            }
        }

        function parse(payload) {
            if (payload === "" || payload === null || payload === undefined) return null;
            return JSON.parse(payload);
        }

        // 宿主调用：载入 CommonJS bundle（插件为单文件产物，不支持运行时 require）
        globalThis.__loadBundle = function (code) {
            var module = { exports: {} };
            var wrapper = new Function("module", "exports", "require", code);
            wrapper(module, module.exports, function (name) {
                throw new Error("插件为单文件 bundle，不支持运行时依赖: " + name);
            });
            pluginExports = module.exports || {};
        };

        // 宿主调用：执行某个 fnPath，结果通过 __nativeInvokeResolve 异步回传
        globalThis.__invokePlugin = function (fnPath, payloadJson) {
            try {
                var fn = pluginExports[fnPath];
                if (typeof fn !== "function") {
                    throw new Error("插件未实现 " + fnPath);
                }
                Promise.resolve(fn(parse(payloadJson))).then(
                    function (result) { __nativeInvokeResolve(true, stringify(result)); },
                    function (error) { __nativeInvokeResolve(false, describe(error)); }
                );
            } catch (error) {
                __nativeInvokeResolve(false, describe(error));
            }
        };

        // 宿主回调：异步路由的结果
        globalThis.__nativeCallResolve = function (id, ok, payload) {
            var entry = pending.get(id);
            if (!entry) return;
            pending.delete(id);
            if (!ok) {
                entry.reject(new Error(payload));
                return;
            }
            try {
                entry.resolve(parse(payload));
            } catch (error) {
                entry.reject(new Error("宿主返回值解析失败: " + describe(error)));
            }
        };

        function hostCall(route, args) {
            return new Promise(function (resolve, reject) {
                var id = ++sequence;
                pending.set(id, { resolve: resolve, reject: reject });
                __nativeCall(id, route, stringify(args));
            });
        }

        function hostCallSync(route, args) {
            var raw = __nativeCallSync(route, stringify(args));
            if (raw === null || raw === undefined || raw === "") return null;
            var envelope = JSON.parse(raw);
            if (!envelope.ok) throw new Error(envelope.payload);
            return parse(envelope.payload);
        }

        globalThis.bridge = {
            call: function (route) {
                return hostCall(route, Array.prototype.slice.call(arguments, 1));
            },
            callSync: function (route) {
                return hostCallSync(route, Array.prototype.slice.call(arguments, 1));
            },
            gzipCompress: function (input) {
                return hostCall("compression.gzip_compress", [input]);
            },
            gzipDecompress: function (input) {
                return hostCall("compression.gzip_decompress", [input]);
            }
        };

        function logger(level) {
            return function () {
                var parts = Array.prototype.slice.call(arguments).map(describe);
                __nativeLog(level, parts.join(" "));
            };
        }

        globalThis.console = {
            log: logger("log"),
            info: logger("info"),
            warn: logger("warn"),
            error: logger("error"),
            debug: logger("debug")
        };
    })();
    """#
}
