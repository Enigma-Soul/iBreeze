import SwiftUI

/// 悬浮玻璃标签栏：三个主标签合成一条，设置单独一颗圆钮放在最右。
///
/// 不用系统 TabView 是为了让它在滚动中隐藏、并保持液态玻璃质感；
/// 代价是要自己补上无障碍标签与 44pt 点按区域。
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            tabs
            settingsButton
        }
        .padding(.horizontal, 16)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                button(for: tab)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 54)
        .glassSurface(in: Capsule())
    }

    private var settingsButton: some View {
        Button(action: onSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 17))
                .frame(width: 54, height: 54)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassSurface(in: Circle())
        .accessibilityLabel("设置")
    }

    private func button(for tab: AppTab) -> some View {
        let isSelected = selection == tab

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selection = tab }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                Text(tab.title)
                    .font(.system(size: 10))
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
    FloatingTabBar(selection: $selection) {}
        .padding(.vertical, 40)
}
