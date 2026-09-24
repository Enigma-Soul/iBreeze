import Foundation
import os

/// 已安装插件的持久化。
///
/// bundle 以文件形式落在 `Application Support/Plugins/<uuid>.cjs`，
/// 元数据统一放在同目录的 `index.json`；没有用数据库是刻意的：
/// bundle 是几百 KB 的文本，放文件更好排查，也便于用户手动导入导出。
final class PluginStore: @unchecked Sendable {
    static let shared = PluginStore()

    private let logger = Logger(subsystem: "com.enigma-soul.ibreeze", category: "PluginStore")
    /// 插件目录，测试里会传临时目录
    let directory: URL
    private let indexURL: URL
    private let lock = NSLock()
    private var index: [String: InstalledPlugin]

    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory()
        self.directory = base
        indexURL = base.appendingPathComponent("index.json")
        index = Self.loadIndex(at: indexURL)

        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    /// 已安装插件，按名称排序
    func installed() -> [InstalledPlugin] {
        lock.lock()
        defer { lock.unlock() }
        return index.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func plugin(uuid: String) -> InstalledPlugin? {
        lock.lock()
        defer { lock.unlock() }
        return index[uuid]
    }

    /// 读取插件 bundle 源码
    func bundle(for uuid: String) throws -> String {
        try String(contentsOf: bundleURL(for: uuid), encoding: .utf8)
    }

    /// 写入插件（已存在则覆盖，保留首次安装时间）
    func save(_ plugin: InstalledPlugin, bundle: String) throws {
        lock.lock()
        var record = plugin
        if let existing = index[plugin.uuid] {
            record.installedAt = existing.installedAt
        }
        index[plugin.uuid] = record
        let snapshot = index
        lock.unlock()

        try bundle.write(to: bundleURL(for: plugin.uuid), atomically: true, encoding: .utf8)
        try persist(snapshot)
        logger.info("已保存插件 \(plugin.name, privacy: .public) \(plugin.version, privacy: .public)")
    }

    /// 只更新元数据（例如检查更新后写回 getInfo 缓存）
    func update(_ plugin: InstalledPlugin) throws {
        lock.lock()
        guard index[plugin.uuid] != nil else {
            lock.unlock()
            return
        }
        index[plugin.uuid] = plugin
        let snapshot = index
        lock.unlock()
        try persist(snapshot)
    }

    func remove(uuid: String) throws {
        lock.lock()
        index.removeValue(forKey: uuid)
        let snapshot = index
        lock.unlock()

        try? FileManager.default.removeItem(at: bundleURL(for: uuid))
        try persist(snapshot)
    }

    private func bundleURL(for uuid: String) -> URL {
        directory.appendingPathComponent("\(uuid).cjs")
    }

    private func persist(_ snapshot: [String: InstalledPlugin]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: indexURL, options: .atomic)
    }

    private static func loadIndex(at url: URL) -> [String: InstalledPlugin] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: InstalledPlugin].self, from: data)) ?? [:]
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Plugins", isDirectory: true)
    }
}
