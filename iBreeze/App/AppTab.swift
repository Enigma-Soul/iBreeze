import Foundation

/// 底部标签页
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case search
    case favorites
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .search: "搜索"
        case .favorites: "收藏"
        case .settings: "设置"
        }
    }

    /// 交给系统标签栏的都是线框图标，选中态由系统自己换实心
    var systemImage: String {
        switch self {
        case .home: "house"
        case .search: "magnifyingglass"
        case .favorites: "heart"
        case .settings: "gearshape"
        }
    }
}
