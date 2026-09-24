import SwiftUI

/// 根视图：首页 / 搜索 / 收藏 三个标签页
struct RootView: View {
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                HomeView()
            }

            Tab(AppTab.search.title, systemImage: AppTab.search.systemImage, value: AppTab.search) {
                SearchView()
            }

            Tab(AppTab.favorites.title, systemImage: AppTab.favorites.systemImage, value: AppTab.favorites) {
                FavoritesView()
            }
        }
        .modifier(MinimizeTabBarOnScroll())
    }
}

/// iOS 26 起支持滚动时收起标签栏
private struct MinimizeTabBarOnScroll: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

#Preview {
    RootView()
}
