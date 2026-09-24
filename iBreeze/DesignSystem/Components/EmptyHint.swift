import SwiftUI

/// 区块空态提示，占位高度与真实内容观感接近，避免加载完成后跳动
struct EmptyHint: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
            Text(text)
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, AppTheme.Spacing.page)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .padding(.horizontal, AppTheme.Spacing.page)
    }
}

#Preview {
    EmptyHint(icon: "clock.arrow.circlepath", text: "还没有浏览记录")
}
