import SwiftUI

/// 卡片底板：分组背景色 + 连续圆角 + 轻投影
struct CardSurface<Content: View>: View {
    var cornerRadius: CGFloat = AppTheme.Radius.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}
