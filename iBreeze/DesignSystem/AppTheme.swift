import SwiftUI
import UIKit

/// 全局视觉常量，样式统一从这里取
enum AppTheme {
    /// 间距
    enum Spacing {
        /// 页面左右边距
        static let page: CGFloat = 16
        /// 区块之间的纵向间距
        static let section: CGFloat = 24
        /// 卡片网格间距
        static let grid: CGFloat = 12
    }

    /// 圆角
    enum Radius {
        static let card: CGFloat = 16
        static let chip: CGFloat = 12
    }

    /// 卡片底板色
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
}
