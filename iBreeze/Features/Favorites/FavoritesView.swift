import SwiftUI

/// 收藏页：本地收藏的漫画，单列行展示
struct FavoritesView: View {
    private var favorites = FavoritesStore.shared

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
                    list
                }
            }
            .navigationTitle(AppTab.favorites.title)
            .appNavigationDestinations()
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(favorites.entries) { entry in
                    NavigationLink(value: AppRoute.comicDetail(sourceID: entry.source, comicID: entry.comicID)) {
                        row(for: entry)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("取消收藏", role: .destructive) {
                            favorites.remove(source: entry.source, comicID: entry.comicID)
                        }
                    }

                    Divider().padding(.leading, AppTheme.Size.listThumbnail.width + 12)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.page)
        }
        .tracksTabBarVisibility()
    }

    private func row(for entry: FavoriteEntry) -> some View {
        ComicRowLayout {
            PluginImageView(sourceID: entry.source, url: entry.coverURL)
        } details: {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title.convertedChinese)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Text(entry.addedAt.formatted(date: .numeric, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
