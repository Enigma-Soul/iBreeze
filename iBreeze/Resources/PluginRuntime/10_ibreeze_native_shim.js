// iBreeze 插件运行时 · 原生层垫片（在 Breeze polyfill 之前注入）
//
// 职责：把 Breeze JS 运行时需要的原生能力接到 iBreeze 的宿主总线上。
// 能在 JS 里做的事（缓冲区池、Base64）就不跨语言，只有网络、定时器、日志
// 这几类真原生能力才回调 Swift。
(function () {
  "use strict";

  var pending = new Map();
  var sequence = 0;

  /// 描述错误：附带前几层调用栈，便于定位插件内部的异常
  function describe(error) {
    if (error === null || error === undefined) return "未知错误";
    if (typeof error === "string") return error;

    var message = error.message ? String(error.message) : String(error);
    if (error.stack) {
      var frames = String(error.stack)
        .split("\n")
        .slice(1, 5)
        .map(function (line) { return line.trim().replace(/^at\s+/, ""); })
        .filter(Boolean);
      if (frames.length > 0) message += " {" + frames.join(" ← ") + "}";
    }
    return message;
  }

  function toBytes(input) {
    if (input instanceof Uint8Array) return input;
    if (input instanceof ArrayBuffer) return new Uint8Array(input);
    if (ArrayBuffer.isView(input)) {
      return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    }
    if (Array.isArray(input)) return Uint8Array.from(input);
    if (typeof input === "string") return new TextEncoder().encode(input);
    throw new TypeError("需要 Uint8Array / ArrayBuffer 类型的二进制数据");
  }

  var BASE64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

  function bytesToBase64(bytes) {
    var binary = "";
    for (var i = 0; i < bytes.length; i += 1) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
  }

  function bytesFromBase64(text) {
    var binary = atob(text);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i += 1) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }

  // btoa/atob 在 JavaScriptCore 里不存在，这里补上
  if (typeof globalThis.btoa !== "function") {
    globalThis.btoa = function (input) {
      var text = String(input);
      var output = "";
      for (var i = 0; i < text.length; i += 3) {
        var c1 = text.charCodeAt(i);
        var c2 = text.charCodeAt(i + 1);
        var c3 = text.charCodeAt(i + 2);
        output += BASE64_CHARS.charAt(c1 >> 2);
        output += BASE64_CHARS.charAt(((c1 & 3) << 4) | (isNaN(c2) ? 0 : c2 >> 4));
        output += isNaN(c2) ? "=" : BASE64_CHARS.charAt(((c2 & 15) << 2) | (isNaN(c3) ? 0 : c3 >> 6));
        output += isNaN(c3) ? "=" : BASE64_CHARS.charAt(c3 & 63);
      }
      return output;
    };
  }

  /// 取 Base64 字符值；越界或填充符返回 -1
  function base64Value(text, index) {
    if (index < 0 || index >= text.length) return -1;
    return BASE64_CHARS.indexOf(text.charAt(index));
  }

  if (typeof globalThis.atob !== "function") {
    globalThis.atob = function (input) {
      var text = String(input);
      var output = "";
      for (var i = 0; i < text.length; i += 4) {
        var n1 = base64Value(text, i);
        var n2 = base64Value(text, i + 1);
        var n3 = base64Value(text, i + 2);
        var n4 = base64Value(text, i + 3);
        if (n1 < 0 || n2 < 0) break;
        output += String.fromCharCode((n1 << 2) | (n2 >> 4));
        if (n3 >= 0) output += String.fromCharCode(((n2 & 15) << 4) | (n3 >> 2));
        if (n4 >= 0) output += String.fromCharCode(((n3 & 3) << 6) | n4);
      }
      return output;
    };
  }

  // ---- 宿主调用总线：JS → Swift ----
  function hostCall(route, args) {
    return new Promise(function (resolve, reject) {
      var id = ++sequence;
      pending.set(id, { resolve: resolve, reject: reject });
      __nativeCall(id, route, stringifyArguments(args || []));
    });
  }

  function hostCallSync(route, args) {
    var raw = __nativeCallSync(route, stringifyArguments(args || []));
    if (raw === null || raw === undefined || raw === "") return null;
    var envelope = JSON.parse(raw);
    if (!envelope.ok) throw new Error(envelope.payload);
    return parseJSON(envelope.payload);
  }

  globalThis.__nativeCallResolve = function (id, ok, payload) {
    var entry = pending.get(id);
    if (!entry) return;
    pending.delete(id);
    if (!ok) {
      entry.reject(new Error(payload));
      return;
    }
    try {
      entry.resolve(parseJSON(payload));
    } catch (error) {
      entry.reject(new Error("宿主返回值解析失败: " + describe(error)));
    }
  };

  function parseJSON(payload) {
    if (payload === "" || payload === null || payload === undefined) return null;
    return JSON.parse(payload);
  }

  /// 把嵌套的二进制转成字节数组：Breeze 的宿主路由就是按数组收字节的
  function toJSONValue(value) {
    if (value === null || value === undefined) return null;
    if (value instanceof Uint8Array) return Array.prototype.slice.call(value);
    if (value instanceof ArrayBuffer) return Array.prototype.slice.call(new Uint8Array(value));
    if (ArrayBuffer.isView(value)) {
      return Array.prototype.slice.call(new Uint8Array(value.buffer, value.byteOffset, value.byteLength));
    }
    if (Array.isArray(value)) return value.map(toJSONValue);
    if (typeof value === "object") {
      var plain = {};
      Object.keys(value).forEach(function (key) {
        plain[key] = toJSONValue(value[key]);
      });
      return plain;
    }
    return value;
  }

  /// 出参序列化：顶层二进制用 Base64 信封，其余走普通 JSON
  function safeStringify(value) {
    if (value === undefined) return "null";
    if (value instanceof Uint8Array) {
      return JSON.stringify({ __ibreezeBinary: bytesToBase64(value) });
    }
    if (value instanceof ArrayBuffer) {
      return JSON.stringify({ __ibreezeBinary: bytesToBase64(new Uint8Array(value)) });
    }
    try {
      return JSON.stringify(value);
    } catch (error) {
      return JSON.stringify({ error: "无法序列化为 JSON: " + describe(error) });
    }
  }

  /// 入参序列化
  function stringifyArguments(value) {
    try {
      return JSON.stringify(toJSONValue(value));
    } catch (error) {
      return JSON.stringify({ error: "参数无法序列化为 JSON: " + describe(error) });
    }
  }

  // ---- 原生缓冲区池：字节留在 JS 侧，只有网络/加密才跨语言 ----
  var buffers = new Map();
  var nextBufferId = 1;

  function putBuffer(input) {
    var id = nextBufferId;
    nextBufferId += 1;
    buffers.set(id, toBytes(input));
    return id;
  }

  function takeBuffer(id) {
    var bytes = buffers.get(Number(id));
    if (bytes === undefined) throw new Error("缓冲区不存在: " + id);
    return bytes;
  }

  function cloneBuffer(id) {
    return new Uint8Array(takeBuffer(id));
  }

  globalThis.__native_buffer_put_raw = function (input) {
    return putBuffer(input);
  };

  globalThis.__native_buffer_put = function (jsonArray) {
    return JSON.stringify({ ok: true, id: putBuffer(JSON.parse(jsonArray)) });
  };

  globalThis.__native_buffer_take_raw = function (id) {
    return cloneBuffer(id);
  };

  globalThis.__native_buffer_take_typed = function (id) {
    return cloneBuffer(id).buffer;
  };

  globalThis.__native_buffer_take = function (id) {
    var bytes = takeBuffer(id);
    return JSON.stringify({ ok: true, data: Array.prototype.slice.call(bytes) });
  };

  globalThis.__native_buffer_clone_raw = function (id) {
    return cloneBuffer(id);
  };

  globalThis.__native_buffer_clone_typed = function (id) {
    return cloneBuffer(id).buffer;
  };

  globalThis.__native_buffer_free = function (id) {
    buffers.delete(Number(id));
    return JSON.stringify({ ok: true });
  };

  globalThis.__base64_encode_native_buffer = function (id) {
    return bytesToBase64(takeBuffer(id));
  };

  globalThis.__base64_decode_to_native_buffer = function (text) {
    return putBuffer(bytesFromBase64(text));
  };

  // 图片处理类 op 暂未实现，明确报错好过静默出错
  globalThis.__native_exec = function (op) {
    return JSON.stringify({ ok: false, error: "尚未实现的原生操作: " + op });
  };

  globalThis.__native_exec_chain = function () {
    return JSON.stringify({ ok: false, error: "尚未实现的原生操作链" });
  };

  // ---- fetch 的宿主接口 ----
  var nextRequestId = 1;

  globalThis.__http_request_promise = function (method, url, headersJson, bodyText, bodyBufferId) {
    var requestId = nextRequestId;
    nextRequestId += 1;

    var headers = {};
    try {
      headers = headersJson ? JSON.parse(headersJson) : {};
    } catch (error) {
      headers = {};
    }

    var bodyBase64 = null;
    if (bodyBufferId !== null && bodyBufferId !== undefined) {
      bodyBase64 = bytesToBase64(takeBuffer(bodyBufferId));
    }

    var promise = hostCall("http.request", [
      requestId,
      String(method || "GET"),
      String(url || ""),
      headers,
      bodyText === undefined ? null : bodyText,
      bodyBase64
    ])
      .then(function (payload) {
        if (!payload || payload.ok !== true) {
          return JSON.stringify({
            ok: false,
            canceled: payload && payload.canceled === true,
            error: (payload && payload.error) || "网络请求失败"
          });
        }
        var bytes = bytesFromBase64(payload.bodyBase64 || "");
        return JSON.stringify({
          ok: true,
          status: payload.status,
          statusText: payload.statusText,
          headers: payload.headers || {},
          url: payload.url || url,
          nativeBufferId: putBuffer(bytes),
          offloadedBytes: bytes.length
        });
      })
      .catch(function (error) {
        return JSON.stringify({ ok: false, error: describe(error) });
      });

    promise.__hostRequestId = requestId;
    return promise;
  };

  globalThis.__http_request_cancel = function (requestId) {
    hostCall("http.cancel", [Number(requestId)]).catch(function () {});
  };

  // ---- 加密：同步桥到 Swift（Breeze 的 __crypto_* 钩子约定：字节数组进，{hex, base64} 出）----
  function cryptoHook(route, arity) {
    return function () {
      var args = Array.prototype.slice.call(arguments, 0, arity).map(function (item) {
        if (item === null || item === undefined) return null;
        if (Array.isArray(item)) return item;
        return Array.prototype.slice.call(toBytes(item));
      });
      return hostCallSync(route, args);
    };
  }

  globalThis.__crypto_sha1_bytes = cryptoHook("crypto.sha1_bytes", 1);
  globalThis.__crypto_sha256_bytes = cryptoHook("crypto.sha256_bytes", 1);
  globalThis.__crypto_sha512_bytes = cryptoHook("crypto.sha512_bytes", 1);
  globalThis.__crypto_hmac_sha1_bytes = cryptoHook("crypto.hmac_sha1_bytes", 2);
  globalThis.__crypto_hmac_sha256_bytes = cryptoHook("crypto.hmac_sha256_bytes", 2);
  globalThis.__crypto_hmac_sha512_bytes = cryptoHook("crypto.hmac_sha512_bytes", 2);
  globalThis.__crypto_pbkdf2_sha256_bytes = cryptoHook("crypto.pbkdf2_sha256_bytes", 4);
  globalThis.__crypto_aes_cbc_pkcs7_encrypt_bytes = cryptoHook("crypto.aes_cbc_pkcs7_encrypt_bytes", 3);
  globalThis.__crypto_aes_cbc_pkcs7_decrypt_bytes = cryptoHook("crypto.aes_cbc_pkcs7_decrypt_bytes", 3);
  globalThis.__crypto_aes_gcm_encrypt_bytes = cryptoHook("crypto.aes_gcm_encrypt_bytes", 4);
  globalThis.__crypto_aes_gcm_decrypt_bytes = cryptoHook("crypto.aes_gcm_decrypt_bytes", 4);
  globalThis.__crypto_timing_safe_equal_bytes = cryptoHook("crypto.timing_safe_equal_bytes", 2);

  globalThis.__crypto_random_bytes = function (size) {
    return hostCallSync("crypto.random_bytes", [Number(size) || 0]);
  };

  globalThis.__crypto_random_uuid_v4 = function () {
    return hostCallSync("crypto.random_uuid_v4", []);
  };

  // ---- 定时器：交给 Swift 的真定时器 ----
  globalThis.__timer_start_evented = function (delayMs, isInterval) {
    // 布尔统一转成 0/1 过桥，避免不同 JS 引擎的布尔桥接差异
    return __nativeTimerStart(Number(delayMs) || 0, isInterval === true ? 1 : 0);
  };

  globalThis.__timer_drop_evented = function (hostId) {
    __nativeTimerDrop(Number(hostId));
  };

  // ---- 日志 ----
  globalThis.__log_emit = function (level, message) {
    __nativeLog(String(level), String(message));
  };

  globalThis.__ibreeze = {
    hostCall: hostCall,
    hostCallSync: hostCallSync,
    describe: describe,
    stringify: safeStringify,
    parse: parseJSON,
    toBytes: toBytes,
    bytesToBase64: bytesToBase64,
    bytesFromBase64: bytesFromBase64
  };
})();
