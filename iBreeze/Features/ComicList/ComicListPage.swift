import SwiftUI

/// 插件列表页：封面网格 + 触底续拉
struct ComicListPage: View {
    let sourceID: String
    let fnPath: String
    let title: String
    let core: JSONValue?
    let extern: JSONValue?

    @State private var viewModel: ComicListViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 180), spacing: AppTheme.Spacing.grid)
    ]

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
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.grid) {
                ForEach(viewModel.items) { item in
                    NavigationLink(value: AppRoute.comicDetail(sourceID: sourceID, comicID: item.id)) {
                        ComicCoverCard(item: item, sourceID: sourceID)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.page)

            footer
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { if viewModel.items.isEmpty { await viewModel.loadMore() } }
        .overlay { emptyOverlay }
    }

    @ViewBuilder
    private var footer: some View {
        if viewModel.isLoading {
            ProgressView()
                .padding(.vertical, 20)
        } else if let message = viewModel.errorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
        } else if viewModel.hasReachedMax, !viewModel.items.isEmpty {
            Text("已经到底了")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
        } else if !viewModel.items.isEmpty {
            // 触底哨兵
            ProgressView()
                .padding(.vertical, 20)
                .onAppear { Task { await viewModel.loadMore() } }
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if viewModel.items.isEmpty, !viewModel.isLoading, let message = viewModel.errorMessage {
            ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }
}
