import SwiftUI

/// 漫画卡片：封面 + 标题 + 副标题
struct ComicCoverCard: View {
    let item: ComicListItem
    let sourceID: String
    var width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PluginImageView(sourceID: sourceID, url: item.cover?.url)
                .frame(width: width, height: width.map { $0 * 4 / 3 })
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))

            Text(item.title.convertedChinese)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle.convertedChinese)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// 横滑区块里的小卡片：固定宽度，用于浏览记录与推荐位
struct ComicPosterRow: View {
    let items: [ComicListItem]
    let sourceID: String
    let route: (ComicListItem) -> AppRoute

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.grid) {
                ForEach(items) { item in
                    NavigationLink(value: route(item)) {
                        ComicCoverCard(item: item, sourceID: sourceID, width: 110)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.page)
        }
    }
}
