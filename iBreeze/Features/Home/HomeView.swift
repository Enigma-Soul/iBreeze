import SwiftUI

/// 首页：插件入口 + 浏览记录 + 插件源推荐漫画
struct HomeView: View {
    @Environment(PluginRegistry.self) private var registry

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    PluginRowSection()
                    BrowsingHistorySection()
                    RecommendedComicsSection()
                }
                .padding(.vertical, AppTheme.Spacing.section)
            }
            .navigationTitle(AppTab.home.title)
            .appNavigationDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
        }
        .onAppear { registry.reload() }
    }
}
