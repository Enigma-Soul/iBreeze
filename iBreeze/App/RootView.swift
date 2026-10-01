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
    /// 任何插件调用报「未授权」都会落到这里，由根视图弹一次登录表单
    @State private var login = PluginLoginCenter.shared

    private var isTabBarHidden: Bool { tabBar.isHidden || isHiddenByChildPage }

    var body: some View {
        @Bindable var login = login

        return ZStack {
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
        // 提示叠在最上层右上角：比起强制弹窗，它不打断正在做的事
        .overlay { ToastHost() }
        .sheet(isPresented: $showsSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(item: $login.request) { request in
            PluginLoginSheet(
                pluginID: request.pluginID,
                pluginName: request.pluginName,
                notice: request.message
            )
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
