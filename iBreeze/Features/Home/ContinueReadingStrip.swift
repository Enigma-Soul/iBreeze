import SwiftUI

/// 「继续阅读」：最近读过的条目。它是列表的头部，会跟着往上滚到插件图标下面，
/// 下面的入口选项卡滚到顶则钉住不动
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

    /// 一律先进详情页：直接进阅读器会跳过封面与章节选择，误点一下就要退两次
    private func route(for entry: ReadingHistoryEntry) -> AppRoute {
        .comicDetail(sourceID: entry.source, comicID: entry.comicID)
    }
}
