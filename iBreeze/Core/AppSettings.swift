import Foundation
import SwiftUI

/// UserDefaults 键名，避免各处硬编码字符串
enum SettingsKey {
    static let proxyEnabled = "proxy.enabled"
    static let proxyType = "proxy.type"
    static let proxyHost = "proxy.host"
    static let proxyPort = "proxy.port"
    static let chineseConversion = "language.chineseConversion"
    static let readingDirection = "reader.direction"
    static let appearance = "appearance.mode"
}

/// 外观模式
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 阅读方向
enum ReadingDirection: String, CaseIterable, Identifiable {
    case vertical
    case leftToRight
    case rightToLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vertical: "纵向连续"
        case .leftToRight: "左右翻页"
        case .rightToLeft: "右到左翻页"
        }
    }

    /// 横向分页模式
    var isPaged: Bool { self != .vertical }
}

/// 网络代理类型
enum ProxyType: String, CaseIterable, Identifiable {
    case http
    case socks5

    var id: String { rawValue }

    var title: String {
        switch self {
        case .http: "HTTP"
        case .socks5: "SOCKS5"
        }
    }
}

/// 简繁中文转换模式
enum ChineseConversion: String, CaseIterable, Identifiable {
    case off
    case toSimplified
    case toTraditional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "关闭"
        case .toSimplified: "转为简体"
        case .toTraditional: "转为繁体"
        }
    }
}
