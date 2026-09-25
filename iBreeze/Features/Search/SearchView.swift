import SwiftUI

/// 搜索页：顶部搜索框 + 搜索记录，默认在全部插件里搜。
///
/// 不用系统 `.searchable`：在带自绘底部标签栏的页面上，它会把搜索框放到屏幕底部，
/// 与浮条叠在一起点不到，所以这里自绘一个置顶的胶囊输入框。
struct SearchView: View {
    @Environment(PluginRegistry.self) private var registry
    @State private var viewModel = SearchViewModel()

    private var history = SearchHistoryStore.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchField(
                    text: $viewModel.keyword,
                    placeholder: "搜索漫画，默认搜全部插件",
                    onSubmit: submit
                )

                if viewModel.items.isEmpty {
                    emptyContent
                } else {
                    ComicResultList(
                        items: viewModel.items,
                        isLoading: viewModel.isLoading,
                        hasReachedMax: viewModel.hasReachedMax,
                        loadMore: { Task { await viewModel.loadMore() } }
                    )
                }
            }
            .navigationTitle(AppTab.search.title)
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationDestinations()
            .toolbar { sourceMenu }
        }
    }

    // MARK: - 范围选择

    @ToolbarContentBuilder
    private var sourceMenu: some ToolbarContent {
        if registry.installed.count > 0 {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("全部插件") { select(sourceID: nil) }

                    ForEach(registry.installed) { plugin in
                        Button(plugin.name) { select(sourceID: plugin.uuid) }
                    }
                } label: {
                    Label(searchScopeTitle, systemImage: "line.3.horizontal.decrease.circle")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote)
                }
            }
        }
    }

    private var searchScopeTitle: String {
        guard let selected = viewModel.selectedSourceID,
              let plugin = registry.plugin(uuid: selected)
        else { return "全部插件" }
        return plugin.name
    }

    private func select(sourceID: String?) {
        viewModel.selectedSourceID = sourceID
        if !viewModel.keyword.trimmingCharacters(in: .whitespaces).isEmpty {
            submit()
        }
    }

    // MARK: - 未搜索时的内容

    @ViewBuilder
    private var emptyContent: some View {
        if viewModel.keyword.trimmingCharacters(in: .whitespaces).isEmpty, !history.keywords.isEmpty {
            historySection
        } else {
            ContentUnavailableView {
                Label("搜索漫画", systemImage: "magnifyingglass")
            } description: {
                Text(viewModel.errorMessage ?? "输入关键词后回车，默认搜全部插件")
            }
        }
    }

    private var historySection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("搜索记录")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("清空") { history.clear() }
                        .font(.footnote)
                }
                .padding(.horizontal, AppTheme.Spacing.page)

                FlowLayout(spacing: 8) {
                    ForEach(history.keywords, id: \.self) { keyword in
                        Button {
                            viewModel.keyword = keyword
                            submit()
                        } label: {
                            Text(keyword)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("删除", role: .destructive) { history.remove(keyword) }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.page)
            }
            .padding(.vertical, 12)
        }
        .tracksTabBarVisibility()
    }

    // MARK: - 提交

    private func submit() {
        let sourceIDs = searchSourceIDs
        guard !sourceIDs.isEmpty else { return }
        Task { await viewModel.search(sourceIDs: sourceIDs) }
    }

    private var searchSourceIDs: [String] {
        if let selected = viewModel.selectedSourceID, registry.plugin(uuid: selected) != nil {
            return [selected]
        }
        return registry.installed.map(\.uuid)
    }
}
