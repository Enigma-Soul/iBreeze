import SwiftUI

/// 结果列表：搜索、插件内搜索、插件列表页共用，自带触底续拉
struct ComicResultList: View {
    let items: [ComicListItem]
    let sourceID: String
    let isLoading: Bool
    let hasReachedMax: Bool
    let loadMore: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    NavigationLink(value: AppRoute.comicDetail(sourceID: sourceID, comicID: item.id)) {
                        ComicListRow(item: item, sourceID: sourceID)
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 88)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.page)

            footer
        }
        .tracksTabBarVisibility()
    }

    @ViewBuilder
    private var footer: some View {
        if isLoading {
            ProgressView().padding(.vertical, 20)
        } else if hasReachedMax, !items.isEmpty {
            Text("已经到底了")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
        } else if !items.isEmpty {
            ProgressView()
                .padding(.vertical, 20)
                .onAppear(perform: loadMore)
        }
    }
}
