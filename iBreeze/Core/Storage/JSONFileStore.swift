import Foundation

/// 轻量 JSON 文件存储：启动时读一次进内存，写入时整体覆盖。
///
/// 用于体量很小的本地数据（浏览记录、收藏索引），不值得为它们引入数据库。
final class JSONFileStore<Value: Codable & Sendable>: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var value: Value

    init(filename: String, default defaultValue: Value, directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent(filename)
        value = Self.load(url: url) ?? defaultValue
    }

    func read() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func update(_ transform: (inout Value) -> Void) {
        lock.lock()
        transform(&value)
        let snapshot = value
        lock.unlock()
        persist(snapshot)
    }

    private func persist(_ value: Value) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func load(url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Value.self, from: data)
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("iBreeze", isDirectory: true)
    }
}
