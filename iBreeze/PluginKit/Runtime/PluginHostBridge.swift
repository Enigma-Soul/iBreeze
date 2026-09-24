import Foundation
import os

/// 宿主能力路由：插件通过 `bridge.call(route, ...args)` 访问。
///
/// 路由名与 breeze-plugin-kit 中的调用一一对应，返回值统一按 JSON 编码，
/// JS 侧解析后即为插件看到的实际值。
final class PluginHostBridge: @unchecked Sendable {
    private let cache = PluginCache()
    private let config: PluginConfigStore
    private let httpClient = PluginHTTPClient()
    private let logger = Logger(subsystem: "com.enigma-soul.ibreeze", category: "PluginHost")

    init(pluginID: String) {
        config = PluginConfigStore(pluginID: pluginID)
    }

    /// 异步路由
    func dispatch(route: String, argsJSON: String) async throws -> String {
        let args = try Self.decodeArguments(argsJSON)

        switch route {
        // 进程内缓存
        case "cache.get", "cache.get.sync": return try readCache(args)
        case "cache.set", "cache.set.sync": return try writeCache(args)
        case "cache.set_if_absent": return try Self.encode(cache.setIfAbsent(
            try Self.requiredString(args, at: 0, route: route),
            value: try Self.rawJSON(args, at: 1)
        ))
        case "cache.compare_and_set": return try Self.encode(cache.compareAndSet(
            try Self.requiredString(args, at: 0, route: route),
            expected: try Self.rawJSON(args, at: 1),
            next: try Self.rawJSON(args, at: 2)
        ))
        case "cache.delete":
            cache.delete(try Self.requiredString(args, at: 0, route: route))
            return "null"

        // 持久化配置
        case "load_plugin_config": return try Self.encode(config.load(
            key: try Self.requiredString(args, at: 0, route: route),
            fallback: Self.string(args, at: 1) ?? ""
        ))
        case "save_plugin_config":
            config.save(
                key: try Self.requiredString(args, at: 0, route: route),
                value: Self.string(args, at: 1) ?? ""
            )
            return "null"

        // 网络
        case "http.request": return try await handleRequest(args)
        case "http.cancel":
            httpClient.cancel(id: Self.int(args, at: 0))
            return "null"

        // 宿主信息与工具
        case "opencc.convert": return try Self.encode(Self.convertChinese(args))
        case "dart.getAppVersion": return try Self.encode(Self.appVersion)
        case "dart.getLocaleInfo": return try Self.encode(Self.localeInfoJSON())
        case "flutter.showToast":
            if let message = Self.string(args, at: 0) {
                logger.notice("插件提示: \(message, privacy: .public)")
            }
            return "null"
        case "math.add": return try Self.encode(Self.number(args, at: 0) + Self.number(args, at: 1))

        // 运行时状态
        case "runtime.gc": return "null"
        case "runtime.is_task_group_cancelled": return try Self.encode(false)

        // 加密路由数量多且自成一套约定，单独成文件
        default:
            if let payload = try PluginCryptoRoutes.dispatch(route: route, args: args) { return payload }
            throw PluginError.unsupportedRoute(route)
        }
    }

    /// 同步路由：仅供 `callSync` 使用，必须足够快，因此只支持缓存读写
    func dispatchSync(route: String, argsJSON: String) -> String {
        do {
            let args = try Self.decodeArguments(argsJSON)
            switch route {
            case "cache.get.sync": return Self.syncEnvelope(ok: true, payload: try readCache(args))
            case "cache.set.sync": return Self.syncEnvelope(ok: true, payload: try writeCache(args))
            default:
                if let payload = try PluginCryptoRoutes.dispatchSync(route: route, args: args) {
                    return Self.syncEnvelope(ok: true, payload: payload)
                }
                let reason = PluginError.unsupportedRoute("\(route)(sync)").localizedDescription
                return Self.syncEnvelope(ok: false, payload: reason)
            }
        } catch {
            return Self.syncEnvelope(ok: false, payload: error.localizedDescription)
        }
    }

    // MARK: - 路由实现

    /// 读取缓存，返回 JSON 文本；缓存里存的就是 JSON 文本，直接回传避免再包一层字符串
    private func readCache(_ args: [Any]) throws -> String {
        guard let key = Self.string(args, at: 0) else { return "null" }
        return try (cache.get(key) ?? Self.rawJSON(args, at: 1))
    }

    private func writeCache(_ args: [Any]) throws -> String {
        cache.set(try Self.requiredString(args, at: 0, route: "cache.set"), value: try Self.rawJSON(args, at: 1))
        return "null"
    }

    private func handleRequest(_ args: [Any]) async throws -> String {
        let payload = await httpClient.request(
            id: Self.int(args, at: 0),
            method: Self.string(args, at: 1) ?? "GET",
            urlString: Self.string(args, at: 2) ?? "",
            headers: Self.headers(args, at: 3),
            bodyText: Self.string(args, at: 4),
            bodyBase64: Self.string(args, at: 5)
        )
        return try Self.encode(payload)
    }

    private static func convertChinese(_ args: [Any]) throws -> String {
        guard let payload = args.first as? [String: Any], let text = payload["text"] as? String else {
            throw PluginError.invalidPayload("opencc.convert 需要 { text, config }")
        }
        return ChineseConverter.convert(text, config: payload["config"] as? String ?? "t2s.json")
    }

    // MARK: - JSON 辅助

    private static func decodeArguments(_ argsJSON: String) throws -> [Any] {
        guard !argsJSON.isEmpty else { return [] }
        guard let data = argsJSON.data(using: .utf8) else {
            throw PluginError.invalidPayload("参数不是合法 UTF-8")
        }
        let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return value as? [Any] ?? []
    }

    /// 取出第 index 个参数并编码回 JSON 文本
    private static func rawJSON(_ args: [Any], at index: Int) throws -> String {
        guard args.indices.contains(index) else { return "null" }
        return try encode(args[index])
    }

    private static func string(_ args: [Any], at index: Int) -> String? {
        guard args.indices.contains(index) else { return nil }
        return args[index] as? String
    }

    private static func number(_ args: [Any], at index: Int) -> Double {
        guard args.indices.contains(index) else { return 0 }
        return args[index] as? Double ?? 0
    }

    private static func int(_ args: [Any], at index: Int) -> Int {
        Int(number(args, at: index))
    }

    private static func headers(_ args: [Any], at index: Int) -> [String: String] {
        guard args.indices.contains(index), let raw = args[index] as? [String: Any] else { return [:] }
        return raw.reduce(into: [:]) { result, pair in
            result[pair.key] = String(describing: pair.value)
        }
    }

    private static func requiredString(_ args: [Any], at index: Int, route: String) throws -> String {
        guard let value = string(args, at: index) else {
            throw PluginError.invalidPayload("\(route) 第 \(index + 1) 个参数必须是字符串")
        }
        return value
    }

    /// 把 Swift 值编码成 JSON 文本
    private static func encode(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }

    /// callSync 的返回信封：`{ ok, payload }`
    private static func syncEnvelope(ok: Bool, payload: String) -> String {
        let dict: [String: Any] = ["ok": ok, "payload": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            return #"{"ok":false,"payload":"返回信封序列化失败"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    /// 与 Breeze 的 dart.getLocaleInfo 字段对齐
    private static func localeInfoJSON() -> String {
        let zone = TimeZone.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "ZZZZZ"

        let info: [String: Any] = [
            "language": Locale.current.language.languageCode?.identifier ?? "zh",
            "locale": Locale.current.identifier,
            "systemLocale": Locale.current.identifier,
            "timeZone": zone.identifier,
            "timeZoneIANA": zone.identifier,
            "timezoneOffset": formatter.string(from: Date()),
            "timezoneOffsetMinutes": zone.secondsFromGMT() / 60,
            "timezoneName": zone.abbreviation() ?? ""
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: info) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
