import SwiftUI

/// 收藏页：本地收藏的漫画
struct FavoritesView: View {
    private var favorites = FavoritesStore.shared

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 180), spacing: AppTheme.Spacing.grid)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if favorites.entries.isEmpty {
                    ContentUnavailableView(
                        "暂无收藏",
                        systemImage: "heart",
                        description: Text("在漫画详情页点右上角收藏")
                    )
                } else {
                    grid
                }
            }
            .navigationTitle(AppTab.favorites.title)
            .appNavigationDestinations()
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.grid) {
                ForEach(favorites.entries) { entry in
                    NavigationLink(value: AppRoute.comicDetail(sourceID: entry.source, comicID: entry.comicID)) {
                        VStack(alignment: .leading, spacing: 6) {
                            PluginImageView(sourceID: entry.source, url: entry.coverURL)
                                .frame(height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))

                            Text(entry.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("取消收藏", role: .destructive) {
                            favorites.remove(source: entry.source, comicID: entry.comicID)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.page)
        }
    }
}
