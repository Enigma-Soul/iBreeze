import SwiftUI

/// 根视图：首页 / 搜索 / 收藏，底部是自绘的悬浮玻璃标签栏。
///
/// 三个页面用 `ZStack` + 透明度切换而不是 `TabView`：这样切页时各自的
/// 滚动位置与已加载数据都会保留，标签栏也能随滚动收起。
struct RootView: View {
    @State private var selection: AppTab = .home
    @State private var tabBar = TabBarVisibility()
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceMode.system.rawValue
    @State private var showsSettings = false
    /// 二级页面（详情/阅读等）要求隐藏标签栏
    @State private var isHiddenByChildPage = false

    private var isTabBarHidden: Bool { tabBar.isHidden || isHiddenByChildPage }

    var body: some View {
        ZStack {
            ForEach(AppTab.allCases) { tab in
                page(for: tab)
                    .opacity(selection == tab ? 1 : 0)
                    .allowsHitTesting(selection == tab)
            }
        }
        .environment(tabBar)
        .safeAreaInset(edge: .bottom) {
            FloatingTabBar(selection: $selection) { showsSettings = true }
                .offset(y: isTabBarHidden ? 100 : 0)
                .opacity(isTabBarHidden ? 0 : 1)
                .animation(.snappy(duration: 0.25), value: isTabBarHidden)
        }
        .observesFloatingTabBarVisibility { isHiddenByChildPage = $0 }
        .sheet(isPresented: $showsSettings) {
            NavigationStack { SettingsView() }
        }
        .onChange(of: selection) { _, _ in tabBar.reset() }
        .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
    }

    @ViewBuilder
    private func page(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .search: SearchView()
        case .favorites: FavoritesView()
        }
    }
}

#Preview {
    RootView()
        .environment(PluginRegistry.shared)
        .environment(ReadingHistoryStore.shared)
}
