import SwiftUI

/// 搜索页：选择插件后按关键词搜索
struct SearchView: View {
    @Environment(PluginRegistry.self) private var registry
    @State private var viewModel = SearchViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 180), spacing: AppTheme.Spacing.grid)
    ]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(AppTab.search.title)
                .appNavigationDestinations()
                .searchable(text: $viewModel.keyword, prompt: "搜索漫画")
                .onSubmit(of: .search) { submit() }
                .toolbar { sourcePicker }
        }
    }

    @ViewBuilder
    private var content: some View {
        if registry.installed.isEmpty {
            ContentUnavailableView(
                "还没有安装插件",
                systemImage: "puzzlepiece.extension",
                description: Text("去「设置 → 插件管理」安装后再搜索")
            )
        } else if viewModel.items.isEmpty {
            ContentUnavailableView(
                "搜索漫画",
                systemImage: "magnifyingglass",
                description: Text(viewModel.errorMessage ?? "输入关键词后回车")
            )
        } else {
            results
        }
    }

    private var results: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.grid) {
                ForEach(viewModel.items) { item in
                    NavigationLink(value: AppRoute.comicDetail(sourceID: currentSourceID, comicID: item.id)) {
                        ComicCoverCard(item: item, sourceID: currentSourceID)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.page)

            if viewModel.isLoading {
                ProgressView().padding(.vertical, 20)
            } else if !viewModel.hasReachedMax {
                ProgressView()
                    .padding(.vertical, 20)
                    .onAppear { Task { await viewModel.loadMore(sourceID: currentSourceID) } }
            }
        }
    }

    private var currentSourceID: String {
        viewModel.resolvedSourceID(installed: registry.installed) ?? ""
    }

    @ToolbarContentBuilder
    private var sourcePicker: some ToolbarContent {
        if registry.installed.count > 1 {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(registry.installed) { plugin in
                        Button(plugin.name) {
                            viewModel.selectedSourceID = plugin.uuid
                            submit()
                        }
                    }
                } label: {
                    Label("切换插件", systemImage: "puzzlepiece.extension")
                }
            }
        }
    }

    private func submit() {
        guard !currentSourceID.isEmpty else { return }
        let sourceID = currentSourceID
        Task { await viewModel.search(sourceID: sourceID) }
    }
}
