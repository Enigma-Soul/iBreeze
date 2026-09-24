import Foundation

/// 已安装插件：元数据来自安装时调用的 `getInfo`
struct InstalledPlugin: Codable, Hashable, Identifiable, Sendable {
    var uuid: String
    var name: String
    var version: String
    var iconURL: String?
    var describe: String?
    var npmName: String?
    var updateURL: String?
    var home: String?
    /// `getInfo().function` 的缓存，避免每次启动都跑一次 JS
    var functions: [PluginFunctionItem]
    var installedAt: Date
    var updatedAt: Date

    var id: String { uuid }

    init(manifest: PluginManifest, now: Date = Date()) {
        uuid = manifest.uuid
        name = manifest.name
        version = manifest.version ?? "0"
        iconURL = manifest.iconUrl
        describe = manifest.describe
        npmName = manifest.npmName
        updateURL = manifest.updateUrl
        home = manifest.home
        functions = manifest.function ?? []
        installedAt = now
        updatedAt = now
    }
}

/// 版本号比较：兼容 `x.y.z` 与带 `v` 前缀的写法
enum PluginVersion {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) > 0
    }

    /// 逐段比较，缺失的段按 0 处理
    static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = components(lhs)
        let right = components(rhs)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }

    private static func components(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
