import SwiftUI

/// 根视图：底栏交给系统 `TabView`。
///
/// 四个标签里只有搜索用 `role: .search` 声明——系统会把它和前三项隔开、
/// 单独摆到最右边（Pixiv-SwiftUI 就是这种排法）。设置不再是标签页，
/// 改成首页右上角的齿轮，点开是一个抽屉。
struct RootView: View {
    @State private var selection: AppTab = .home
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceMode.system.rawValue
    /// 任何插件调用报「未授权」都会落到这里，由根视图弹一次登录表单
    @State private var login = PluginLoginCenter.shared

    var body: some View {
        @Bindable var login = login

        return TabView(selection: $selection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                HomeView()
            }

            Tab(AppTab.history.title, systemImage: AppTab.history.systemImage, value: AppTab.history) {
                HistoryView()
            }

            Tab(AppTab.favorites.title, systemImage: AppTab.favorites.systemImage, value: AppTab.favorites) {
                FavoritesView()
            }

            Tab(
                AppTab.search.title,
                systemImage: AppTab.search.systemImage,
                value: AppTab.search,
                role: .search
            ) {
                SearchView()
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
}

#Preview {
    RootView()
        .environment(PluginRegistry.shared)
        .environment(ReadingHistoryStore.shared)
}
