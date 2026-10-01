import SwiftUI

/// 标签 chip：详情页与列表行共用同一种形状与配色
struct TagChip: View {
    let text: String

    var body: some View {
        Text(text.convertedChinese)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(uiColor: .tertiarySystemFill))
            .foregroundStyle(.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
