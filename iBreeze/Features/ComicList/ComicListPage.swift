import SwiftUI

/// 插件定义的列表页：单列行 + 触底续拉 + 可选筛选器
struct ComicListPage: View {
    let sourceID: String
    let fnPath: String
    let title: String
    let core: JSONValue?
    let extern: JSONValue?
    let filterFnPath: String?
    let filterCore: JSONValue?
    let filterExtern: JSONValue?

    @State private var viewModel: ComicListViewModel

    init(
        sourceID: String,
        fnPath: String,
        title: String,
        core: JSONValue?,
        extern: JSONValue?,
        filterFnPath: String?,
        filterCore: JSONValue? = nil,
        filterExtern: JSONValue? = nil
    ) {
        self.sourceID = sourceID
        self.fnPath = fnPath
        self.title = title
        self.core = core
        self.extern = extern
        self.filterFnPath = filterFnPath
        self.filterCore = filterCore
        self.filterExtern = filterExtern
        _viewModel = State(initialValue: ComicListViewModel(
            sourceID: sourceID,
            fnPath: fnPath,
            core: core,
            extern: extern,
            filterFnPath: filterFnPath,
            filterCore: filterCore,
            filterExtern: filterExtern
        ))
    }

    var body: some View {
        ComicResultList(
            items: viewModel.items,
            sourceID: sourceID,
            isLoading: viewModel.isLoading,
            hasReachedMax: viewModel.hasReachedMax,
            loadMore: { Task { await viewModel.loadMore() } }
        )
        .navigationTitle(title)
        .hidesFloatingTabBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { filterToolbar }
        .refreshable { await viewModel.refresh() }
        .task {
            await viewModel.loadFilterIfNeeded()
            if viewModel.items.isEmpty { await viewModel.loadMore() }
        }
        .overlay { emptyOverlay }
    }

    @ToolbarContentBuilder
    private var filterToolbar: some ToolbarContent {
        if viewModel.hasFilter {
            ToolbarItem(placement: .topBarTrailing) {
                FilterMenu(
                    title: viewModel.filterTitle,
                    options: viewModel.filterOptions,
                    activeLabel: viewModel.activeFilterLabel
                ) { option in
                    Task { await viewModel.apply(option: option) }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if viewModel.items.isEmpty, !viewModel.isLoading {
            if let message = viewModel.errorMessage {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(message))
            } else {
                ProgressView()
            }
        }
    }
}
