import SwiftUI

/// 单列行的统一排布：左缩略图 + 右侧内容。
///
/// 缩略图尺寸、圆角与行高只在这里定一次，列表页与收藏页因此不会各写一套。
struct ComicRowLayout<Cover: View, Details: View>: View {
    @ViewBuilder var cover: Cover
    @ViewBuilder var details: Details

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            cover
                .frame(width: AppTheme.Size.listThumbnail.width, height: AppTheme.Size.listThumbnail.height)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.thumbnail, style: .continuous))

            details
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: AppTheme.Size.listThumbnail.height)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
