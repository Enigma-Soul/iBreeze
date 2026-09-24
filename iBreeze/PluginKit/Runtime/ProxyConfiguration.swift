import Foundation

/// 代理配置，来源于设置页
struct ProxyConfiguration: Sendable, Equatable {
    var type: ProxyType
    var host: String
    var port: Int

    /// 读取当前设置；未启用或配置不全时返回 nil
    static func current(_ defaults: UserDefaults = .standard) -> ProxyConfiguration? {
        guard defaults.bool(forKey: SettingsKey.proxyEnabled) else { return nil }

        let host = defaults.string(forKey: SettingsKey.proxyHost) ?? ""
        let port = Int(defaults.string(forKey: SettingsKey.proxyPort) ?? "")
        guard !host.isEmpty, let port, port > 0 else { return nil }

        let type = defaults.string(forKey: SettingsKey.proxyType).flatMap(ProxyType.init(rawValue:)) ?? .http
        return ProxyConfiguration(type: type, host: host, port: port)
    }

    /// URLSession 的代理字典。
    ///
    /// 注意：iOS 上 SOCKS5 走系统实现，HTTP 代理的实际支持度依赖系统版本，
    /// 需要在真机上验证。
    var connectionProxyDictionary: [AnyHashable: Any] {
        switch type {
        case .http:
            [
                "HTTPEnable": 1,
                "HTTPProxy": host,
                "HTTPPort": port,
                "HTTPSEnable": 1,
                "HTTPSProxy": host,
                "HTTPSPort": port
            ]
        case .socks5:
            [
                "SOCKSEnable": 1,
                "SOCKSProxy": host,
                "SOCKSPort": port
            ]
        }
    }
}
