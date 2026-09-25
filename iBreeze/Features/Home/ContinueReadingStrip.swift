import SwiftUI

/// 「继续阅读」：最近读过的条目，出现在首页列表的头部
struct ContinueReadingStrip: View {
    private var history = ReadingHistoryStore.shared

    private let posterWidth: CGFloat = 96

    var body: some View {
        if !history.entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("继续阅读")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, AppTheme.Spacing.page)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.grid) {
                        ForEach(history.entries.prefix(10)) { entry in
                            NavigationLink(value: route(for: entry)) {
                                card(for: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.page)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func card(for entry: ReadingHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PluginImageView(sourceID: entry.source, url: entry.coverURL)
                .frame(width: posterWidth, height: posterWidth * 4 / 3)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.thumbnail, style: .continuous))

            Text(entry.title.convertedChinese)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: posterWidth, alignment: .leading)
        }
    }

    /// 有章节就直接续读，否则回详情页
    private func route(for entry: ReadingHistoryEntry) -> AppRoute {
        if let chapterID = entry.chapterID, !chapterID.isEmpty {
            return .reader(
                sourceID: entry.source,
                comicID: entry.comicID,
                chapterID: chapterID,
                chapterName: entry.chapterName ?? "",
                title: entry.title
            )
        }
        return .comicDetail(sourceID: entry.source, comicID: entry.comicID)
    }
}
