import SwiftUI

/// 单个插件内的搜索页。
///
/// 有些插件不声明浏览入口（`getInfo().function` 为空），只能靠关键词搜索，
/// 这个页面就是它们的入口；也可以从插件列表里直接用某一个插件搜索。
struct PluginSearchPage: View {
    let plugin: InstalledPlugin

    @State private var viewModel = SearchViewModel()

    var body: some View {
        Group {
            if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "在 \(plugin.name) 中搜索",
                    systemImage: "magnifyingglass",
                    description: Text(viewModel.errorMessage ?? "输入关键词后回车")
                )
            } else {
                ComicResultGrid(
                    items: viewModel.items,
                    sourceID: plugin.uuid,
                    isLoading: viewModel.isLoading,
                    hasReachedMax: viewModel.hasReachedMax,
                    loadMore: { Task { await viewModel.loadMore(sourceID: plugin.uuid) } }
                )
            }
        }
        .navigationTitle(plugin.name)
        .navigationBarTitleDisplayMode(.inline)
        .appNavigationDestinations()
        .searchable(text: $viewModel.keyword, prompt: "搜索 \(plugin.name)")
        .onSubmit(of: .search) {
            Task { await viewModel.search(sourceID: plugin.uuid) }
        }
    }
}
