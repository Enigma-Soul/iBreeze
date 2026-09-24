import Foundation

/// 插件进程内缓存：生命周期跟随 App 进程，插件重建运行时后依然保留。
///
/// 值统一以 JSON 文本存放，读取时原样返回，插件侧无需二次解析。
final class PluginCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    func get(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ key: String, value: String) {
        lock.lock()
        storage[key] = value
        lock.unlock()
    }

    /// 仅当键不存在时写入，返回是否写入成功
    func setIfAbsent(_ key: String, value: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storage[key] == nil else { return false }
        storage[key] = value
        return true
    }

    /// 比较并交换，返回是否交换成功
    func compareAndSet(_ key: String, expected: String, next: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storage[key] == expected else { return false }
        storage[key] = next
        return true
    }

    func delete(_ key: String) {
        lock.lock()
        storage.removeValue(forKey: key)
        lock.unlock()
    }
}
