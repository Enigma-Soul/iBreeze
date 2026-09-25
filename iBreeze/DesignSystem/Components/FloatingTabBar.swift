import SwiftUI

/// 悬浮玻璃标签栏：一层胶囊贴在底部，滚动时收起。
///
/// 不用系统 TabView 是为了让它在滚动中隐藏、并保持液态玻璃质感；
/// 代价是要自己补上无障碍标签与 44pt 点按区域。
struct FloatingTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                button(for: tab)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 58)
        .glassSurface(in: Capsule())
        .padding(.horizontal, 16)
    }

    private func button(for tab: AppTab) -> some View {
        let isSelected = selection == tab

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                Text(tab.title)
                    .font(.caption2)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    @Previewable @State var selection: AppTab = .home
    FloatingTabBar(selection: $selection)
        .padding(.vertical, 40)
}
