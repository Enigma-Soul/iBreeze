import SwiftUI

/// 搜索页：默认在全部插件里搜，未输入时显示搜索记录。
///
/// 输入框交给系统 `.searchable`：这一页挂在 `role: .search` 的标签下，
/// iOS 26 会把整条底栏变成搜索框（Pixiv-SwiftUI 那种形态），
/// 自己再画一个置顶胶囊框只会多出一份。
struct SearchView: View {
    @Environment(PluginRegistry.self) private var registry
    @State private var viewModel = SearchViewModel()

    private var history = SearchHistoryStore.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
            .searchable(text: $viewModel.keyword, prompt: "搜索漫画，默认搜全部插件")
            .onSubmit(of: .search) { submit() }
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
