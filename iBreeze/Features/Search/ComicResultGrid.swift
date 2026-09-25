import SwiftUI

/// 搜索结果网格：搜索页与「插件内搜索」共用，自带触底续拉
struct ComicResultGrid: View {
    let items: [ComicListItem]
    let sourceID: String
    let isLoading: Bool
    let hasReachedMax: Bool
    let loadMore: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 180), spacing: AppTheme.Spacing.grid)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.grid) {
                ForEach(items) { item in
                    NavigationLink(value: AppRoute.comicDetail(sourceID: sourceID, comicID: item.id)) {
                        ComicCoverCard(item: item, sourceID: sourceID)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.page)

            footer
        }
    }

    @ViewBuilder
    private var footer: some View {
        if isLoading {
            ProgressView().padding(.vertical, 20)
        } else if !hasReachedMax, !items.isEmpty {
            ProgressView()
                .padding(.vertical, 20)
                .onAppear(perform: loadMore)
        }
    }
}
