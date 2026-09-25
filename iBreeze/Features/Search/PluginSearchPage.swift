import SwiftUI

/// 单个插件内的搜索页。
///
/// 有些插件不声明浏览入口（`getInfo().function` 为空），只能靠关键词搜索，
/// 这个页面就是它们的入口；首页搜索框与插件的 `openSearch` 动作也落到这里。
struct PluginSearchPage: View {
    let sourceID: String
    let sourceName: String
    let initialKeyword: String

    @State private var viewModel = SearchViewModel()
    @State private var didSubmitInitial = false

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $viewModel.keyword, placeholder: "搜索 \(sourceName)", onSubmit: submit)

            if viewModel.items.isEmpty {
                emptyState
            } else {
                ComicResultList(
                    items: viewModel.items,
                    sourceID: sourceID,
                    isLoading: viewModel.isLoading,
                    hasReachedMax: viewModel.hasReachedMax,
                    loadMore: { Task { await viewModel.loadMore(sourceID: sourceID) } }
                )
            }
        }
        .navigationTitle(sourceName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await submitInitialKeyword() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("在 \(sourceName) 中搜索", systemImage: "magnifyingglass")
        } description: {
            Text(viewModel.errorMessage ?? "输入关键词后回车")
        } actions: {
            if !SearchHistoryStore.shared.keywords.isEmpty {
                historyChips
            }
        }
    }

    /// 未搜索时给最近用过的关键词
    private var historyChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(SearchHistoryStore.shared.keywords, id: \.self) { keyword in
                Button(keyword) {
                    viewModel.keyword = keyword
                    submit()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: 280)
    }

    private func submit() {
        Task { await viewModel.search(sourceID: sourceID) }
    }

    /// 从插件动作带关键词进来时自动搜一次
    private func submitInitialKeyword() async {
        guard !didSubmitInitial, !initialKeyword.isEmpty else { return }
        didSubmitInitial = true
        viewModel.keyword = initialKeyword
        await viewModel.search(sourceID: sourceID)
    }
}
