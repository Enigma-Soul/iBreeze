import Foundation

extension ChineseConversion {
    /// 当前设置
    static var current: ChineseConversion {
        UserDefaults.standard.string(forKey: SettingsKey.chineseConversion)
            .flatMap(ChineseConversion.init(rawValue:)) ?? .off
    }

    /// 按模式转换用字
    func apply(to text: String) -> String {
        switch self {
        case .off: text
        case .toSimplified: ChineseConverter.convert(text, config: "t2s.json")
        case .toTraditional: ChineseConverter.convert(text, config: "s2t.json")
        }
    }
}

extension String {
    /// 按设置自动转换简繁，用于展示插件返回的标题、章节名等文本
    var convertedChinese: String {
        ChineseConversion.current.apply(to: self)
    }
}
