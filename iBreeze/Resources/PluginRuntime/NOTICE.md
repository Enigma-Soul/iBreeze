# 插件运行时 JS 层

本目录下的 JS 文件分两类。

## 1. 来自 Breeze 的官方运行时（请勿随意改动）

以下文件逐字复制自 [Breeze](https://github.com/deretame/Breeze) 的
`rust/rquickjs_playground/js/`（该目录即 Web 运行时 polyfill，非 playground 专用），
按上游 `src/web_runtime.rs` 的顺序注入：

- `00_bootstrap.js`：全局垫片与 `setTimeout` / `setInterval` 桥接
- `04_runtime_base_polyfills.js`：`TextEncoder`、`Blob`、`FormData`、`Buffer` 等
- `05_structured_clone.js`
- `06_url.js`：`URL` / `URLSearchParams`
- `10_headers.js`：`Headers`
- `20_abort.js`：`AbortController` / `AbortSignal`
- `30_fetch.js`：`fetch` / `Request` / `Response`
- `60_native.js`：原生缓冲区与字节处理 op
- `63_stack_hook.js`
- `70_temporal.js`：第三方 temporal-polyfill（许可证见 `THIRD_PARTY_TEMPORAL_POLYFILL.LICENSE`）
- `99_exports.js`：把 `__web` 上的能力挂到 `globalThis`

上游未注入到本项目的文件：`07_intl.js`（JavaScriptCore 自带完整 `Intl`）、
`50_fs.js`（Breeze 同样不向插件暴露 `fs`）、`62_bridge.js` / `65_console.js`
（由本项目的宿主垫片接管）。

许可证：Breeze 与本项目同为 **MPL-2.0**。上述文件保持 MPL-2.0 授权，
如需修改，修改后的文件同样以 MPL-2.0 提供。

## 2. iBreeze 自己的垫片

- `10_ibreeze_native_shim.js`：把 Breeze polyfill 需要的原生能力接到本项目宿主总线
  （缓冲区池、Base64、`fetch` 的宿主接口、定时器、日志）
- `90_ibreeze_host_shim.js`：`bridge` / `console` 全局对象与 CommonJS bundle 装载

这两个文件是本项目自有代码，同样以 MPL-2.0 授权。
