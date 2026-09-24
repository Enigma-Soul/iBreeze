import Foundation

/// 简繁转换：用 ICU 音译规则实现，配置名与 Breeze 的 `opencc.*` 保持一致
enum ChineseConverter {
    /// 配置名 → ICU 音译方向
    private static let directions: [String: (from: String, to: String)] = [
        "s2t.json": ("Hans", "Hant"),
        "t2s.json": ("Hant", "Hans"),
        "s2tw.json": ("Hans", "Hant"),
        "tw2s.json": ("Hant", "Hans"),
        "s2hk.json": ("Hans", "Hant"),
        "hk2s.json": ("Hant", "Hans")
    ]

    /// 按配置名转换文本，配置未知时原样返回
    static func convert(_ text: String, config: String) -> String {
        guard let direction = directions[config] else { return text }
        let transform = StringTransform("\(direction.from)-\(direction.to)")
        return text.applyingTransform(transform, reverse: false) ?? text
    }
}
