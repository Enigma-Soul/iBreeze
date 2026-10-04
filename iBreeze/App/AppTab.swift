import Foundation

/// 底部标签页。顺序与摆位在 `RootView` 里声明——首页 / 历史 / 收藏平铺，
/// 最后一项搜索带 `role: .search`，系统会把它单独摆到最右边
enum AppTab: Hashable {
    case home
    case history
    case favorites
    case search

    var title: String {
        switch self {
        case .home: "首页"
        case .history: "历史"
        case .favorites: "收藏"
        case .search: "搜索"
        }
    }

    /// 交给系统标签栏的都是线框图标，选中态由系统自己换实心
    var systemImage: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .favorites: "heart"
        case .search: "magnifyingglass"
        }
    }
}
