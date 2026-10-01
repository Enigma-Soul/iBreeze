import SwiftUI

/// 根视图：首页 / 搜索 / 收藏 / 设置，底栏交给系统 `TabView`。
///
/// 之前是自绘玻璃条 + ZStack 透明度切页，为的是把设置拆成独立一颗钮；现在四个
/// 标签平铺，直接用系统标签栏就能拿到 iOS 26 的液态玻璃与「下滚收起」，
/// 也省掉自己补无障碍与点按区域的活。
struct RootView: View {
    @State private var selection: AppTab = .home
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceMode.system.rawValue
    /// 任何插件调用报「未授权」都会落到这里，由根视图弹一次登录表单
    @State private var login = PluginLoginCenter.shared

    var body: some View {
        @Bindable var login = login

        return TabView(selection: $selection) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    page(for: tab)
                }
            }
        }
        .minimizesTabBarOnScroll()
        // 提示叠在最上层右上角：比起强制弹窗，它不打断正在做的事
        .overlay { ToastHost() }
        .sheet(item: $login.request) { request in
            PluginLoginSheet(
                pluginID: request.pluginID,
                pluginName: request.pluginName,
                notice: request.message
            )
        }
        .preferredColorScheme(AppearanceMode(rawValue: appearance)?.colorScheme)
    }

    @ViewBuilder
    private func page(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .search: SearchView()
        case .favorites: FavoritesView()
        case .settings: NavigationStack { SettingsView() }
        }
    }
}

#Preview {
    RootView()
        .environment(PluginRegistry.shared)
        .environment(ReadingHistoryStore.shared)
}
