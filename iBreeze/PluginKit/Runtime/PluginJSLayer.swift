import Foundation

/// 注入插件运行时的 JS 层。
///
/// 分三段：iBreeze 原生垫片 → Breeze 官方 polyfill → iBreeze 宿主垫片。
/// 中间那段来自 Breeze（MPL-2.0），见 `Resources/PluginRuntime/NOTICE.md`。
enum PluginJSLayer {
    /// 原生能力垫片，必须在 polyfill 之前
    private static let nativeShim = "10_ibreeze_native_shim"

    /// 宿主能力垫片，必须在 99_exports 之后（否则会被清空）
    private static let hostShim = "90_ibreeze_host_shim"

    /// 与上游 `web_runtime.rs` 的拼接顺序保持一致：04 提供基础对象，00 再取用它们
    private static let breezePolyfills = [
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
        "99_exports"
    ]

    /// 注入顺序：原生垫片 → Breeze polyfill → 宿主垫片
    private static let scriptNames = [nativeShim] + breezePolyfills + [hostShim]

    /// 组装好的完整脚本，进程内只拼一次
    private static let assembled: String? = {
        let sources = scriptNames.compactMap { try? source(named: $0) }
        // 缺任何一段都算打包出错，避免注入半个运行时
        guard sources.count == scriptNames.count else { return nil }
        return sources.joined(separator: "\n;\n")
    }()

    /// 完整注入脚本；资源缺失时抛错
    static func injectionScript() throws -> String {
        guard let assembled else { throw PluginError.missingRuntimeScript }
        return assembled
    }

    /// 从 App bundle 读取脚本，兼容「保留目录结构」与「平铺」两种打包方式
    private static func source(named name: String) throws -> String {
        let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "PluginRuntime")
            ?? Bundle.main.url(forResource: name, withExtension: "js")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw PluginError.missingRuntimeScript
        }
        return text
    }
}
