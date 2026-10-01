import SwiftUI
import UIKit

/// 全局视觉常量，样式统一从这里取
enum AppTheme {
    /// 间距
    enum Spacing {
        /// 页面左右边距
        static let page: CGFloat = 16
        /// 网格与横滑列表的间距
        static let grid: CGFloat = 12
    }

    /// 圆角
    enum Radius {
        static let card: CGFloat = 16
        static let thumbnail: CGFloat = 8
    }

    /// 尺寸
    enum Size {
        /// 单列列表里缩略图的尺寸，列表行与收藏页共用
        static let listThumbnail = CGSize(width: 76, height: 106)
    }

    /// 卡片底板色
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
}
