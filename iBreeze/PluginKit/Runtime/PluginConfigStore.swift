import Foundation

/// 插件持久化配置：跨 App 重启保留
final class PluginConfigStore: @unchecked Sendable {
    private let defaultsKey: String
    private let lock = NSLock()
    private var values: [String: String]

    init(pluginID: String) {
        defaultsKey = "plugin.config.\(pluginID)"
        values = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    func save(key: String, value: String) {
        lock.lock()
        values[key] = value
        let snapshot = values
        lock.unlock()
        UserDefaults.standard.set(snapshot, forKey: defaultsKey)
    }

    /// 返回 `{"ok":bool,"value":…}` 的 JSON 文本，与 breeze-plugin-kit 的读取约定一致
    func load(key: String, fallback: String) -> String {
        lock.lock()
        let stored = values[key]
        lock.unlock()

        let raw = stored ?? fallback
        let value: Any = (try? JSONSerialization.jsonObject(
            with: Data(raw.utf8),
            options: [.fragmentsAllowed]
        )) ?? raw

        let envelope: [String: Any] = ["ok": stored != nil, "value": value]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: [.fragmentsAllowed]) else {
            return #"{"ok":false,"value":null}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}
