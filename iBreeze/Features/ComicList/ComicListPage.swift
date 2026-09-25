import SwiftUI

/// 插件定义的列表页：单列行 + 触底续拉
struct ComicListPage: View {
    let sourceID: String
    let fnPath: String
    let title: String
    let core: JSONValue?
    let extern: JSONValue?

    @State private var viewModel: ComicListViewModel

    init(sourceID: String, fnPath: String, title: String, core: JSONValue?, extern: JSONValue?) {
        self.sourceID = sourceID
        self.fnPath = fnPath
        self.title = title
        self.core = core
        self.extern = extern
        _viewModel = State(initialValue: ComicListViewModel(
            sourceID: sourceID,
            fnPath: fnPath,
            core: core,
            extern: extern
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
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { if viewModel.items.isEmpty { await viewModel.loadMore() } }
        .overlay { emptyOverlay }
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
