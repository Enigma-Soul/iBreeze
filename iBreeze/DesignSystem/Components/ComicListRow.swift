import SwiftUI

/// 画廊列表行：左侧缩略图，右侧标题与元信息。
///
/// 漫画列表用单列行而不是网格：标题、作者、页数这些信息在网格里放不下，
/// 而挑漫画时这些恰恰是决定点不点进去的关键。
struct ComicListRow: View {
    let item: ComicListItem
    let sourceID: String

    var body: some View {
        ComicRowLayout {
            PluginImageView(sourceID: sourceID, url: item.cover?.url)
        } details: {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title.convertedChinese)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle.convertedChinese)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                metadata
            }
        }
    }

    private var metadata: some View {
        HStack(spacing: 12) {
            if let likes = item.likesCount, likes > 0 {
                Label("\(likes)", systemImage: "heart")
            }
            if let views = item.viewsCount, views > 0 {
                Label("\(views)", systemImage: "eye")
            }
            if let updatedAt = item.updatedAt, !updatedAt.isEmpty {
                Text(updatedAt)
                    .lineLimit(1)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
