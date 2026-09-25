import Foundation

/// 底部标签页
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case search
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .search: "搜索"
        case .favorites: "收藏"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .search: "magnifyingglass"
        case .favorites: "heart"
        }
    }

    /// 选中态用实心图标，和悬浮标签栏的其余状态区分开
    var selectedSystemImage: String {
        switch self {
        case .home: "house.fill"
        case .search: "magnifyingglass"
        case .favorites: "heart.fill"
        }
    }
}
