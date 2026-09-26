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

  /// 查表 + 分块 fromCharCode：逐字符拼接在解释器里慢到不能用，
  /// 几 MB 的图片走一遍就是好几秒
  var BASE64_VALUES = (function () {
    var table = new Int16Array(256);
    for (var i = 0; i < 256; i += 1) table[i] = -1;
    for (var j = 0; j < BASE64_CHARS.length; j += 1) table[BASE64_CHARS.charCodeAt(j)] = j;
    return table;
  })();

  var BASE64_CODES = (function () {
    var codes = new Uint8Array(64);
    for (var i = 0; i < 64; i += 1) codes[i] = BASE64_CHARS.charCodeAt(i);
    return codes;
  })();

  var BASE64_CHUNK = 0x8000;

  function bytesToBase64(bytes) {
    var length = bytes.length;
    var extra = length % 3;
    var main = length - extra;
    var pieces = [];
    var buffer = new Array(BASE64_CHUNK);
    var filled = 0;

    function flush() {
      if (filled === 0) return;
      pieces.push(String.fromCharCode.apply(null, filled === buffer.length ? buffer : buffer.slice(0, filled)));
      filled = 0;
    }

    for (var i = 0; i < main; i += 3) {
      var value = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
      buffer[filled] = BASE64_CODES[(value >> 18) & 63];
      buffer[filled + 1] = BASE64_CODES[(value >> 12) & 63];
      buffer[filled + 2] = BASE64_CODES[(value >> 6) & 63];
      buffer[filled + 3] = BASE64_CODES[value & 63];
      filled += 4;
      if (filled >= BASE64_CHUNK - 4) flush();
    }

    if (extra === 1) {
      var single = bytes[main];
      buffer[filled] = BASE64_CODES[(single >> 2) & 63];
      buffer[filled + 1] = BASE64_CODES[(single & 3) << 4];
      buffer[filled + 2] = 61;
      buffer[filled + 3] = 61;
      filled += 4;
    } else if (extra === 2) {
      var pair = (bytes[main] << 8) | bytes[main + 1];
      buffer[filled] = BASE64_CODES[(pair >> 10) & 63];
      buffer[filled + 1] = BASE64_CODES[(pair >> 4) & 63];
      buffer[filled + 2] = BASE64_CODES[(pair & 15) << 2];
      buffer[filled + 3] = 61;
      filled += 4;
    }

    flush();
    return pieces.join("");
  }

  function bytesFromBase64(text) {
    var source = String(text);
    var length = source.length;
    var padding = 0;

    while (length > 0 && source.charCodeAt(length - 1) === 61) {
      padding += 1;
      length -= 1;
    }

    var bytes = new Uint8Array((length * 3) >> 2);
    var index = 0;
    var i = 0;
    var limit = length - (length % 4);

    for (; i < limit; i += 4) {
      var a = BASE64_VALUES[source.charCodeAt(i)];
      var b = BASE64_VALUES[source.charCodeAt(i + 1)];
      var c = BASE64_VALUES[source.charCodeAt(i + 2)];
      var d = BASE64_VALUES[source.charCodeAt(i + 3)];
      bytes[index] = (a << 2) | (b >> 4);
      bytes[index + 1] = ((b & 15) << 4) | (c >> 2);
      bytes[index + 2] = ((c & 3) << 6) | d;
      index += 3;
    }

    var rest = length % 4;
    if (rest >= 2) {
      var x = BASE64_VALUES[source.charCodeAt(i)];
      var y = BASE64_VALUES[source.charCodeAt(i + 1)];
      bytes[index] = (x << 2) | (y >> 4);
      index += 1;
      if (rest === 3) {
        var z = BASE64_VALUES[source.charCodeAt(i + 2)];
        bytes[index] = ((y & 15) << 4) | (z >> 2);
        index += 1;
      }
    }

    return index === bytes.length ? bytes : bytes.subarray(0, index);
  }

  // btoa/atob 在 JavaScriptCore 里不存在，这里补上
  if (typeof globalThis.btoa !== "function") {
    globalThis.btoa = function (input) {
      return bytesToBase64(toBytes(String(input)));
    };
  }

  if (typeof globalThis.atob !== "function") {
    globalThis.atob = function (input) {
      var bytes = bytesFromBase64(String(input));
      var text = "";
      for (var i = 0; i < bytes.length; i += 1) text += String.fromCharCode(bytes[i]);
      return text;
    };
  }

  // 00_bootstrap 只在缺失时才补这两个全局，这里先占住，
  // 免得插件拿到它那套走 JSON 数组的慢实现
  if (typeof globalThis.bytesToBase64 !== "function") {
    globalThis.bytesToBase64 = bytesToBase64;
  }
  if (typeof globalThis.bytesFromBase64 !== "function") {
    globalThis.bytesFromBase64 = bytesFromBase64;
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
