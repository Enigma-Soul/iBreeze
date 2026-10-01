import SwiftUI

/// 悬浮玻璃标签栏：三个主标签合成一条，设置单独一颗圆钮放在最右。
///
/// 外观照着系统标签栏（Pixiv-SwiftUI 用的就是原生 TabView）做：选中项的图标
/// 落在一条随动的高亮胶囊里，未选中项只有图标与浅色文字。不用原生 TabView
/// 是因为要随滚动隐藏、还要把设置拆成独立一颗；代价是得自己补无障碍与点按区域。
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    let onSettings: () -> Void

    /// 高亮胶囊在标签之间滑动
    @Namespace private var highlight

    private static let barHeight: CGFloat = 56

    var body: some View {
        HStack(spacing: 10) {
            tabs
            settingsButton
        }
        .padding(.horizontal, 16)
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                button(for: tab)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Self.barHeight)
        .glassSurface(in: Capsule())
    }

    private var settingsButton: some View {
        Button(action: onSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: Self.barHeight, height: Self.barHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassSurface(in: Circle())
        .accessibilityLabel("设置")
    }

    private func button(for tab: AppTab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard !isSelected else { return }
            withAnimation(.snappy(duration: 0.25)) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 26)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.18))
                                .matchedGeometryEffect(id: "tabHighlight", in: highlight)
                        }
                    }

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    @Previewable @State var selection: AppTab = .home
    FloatingTabBar(selection: $selection) {}
        .padding(.vertical, 40)
}
