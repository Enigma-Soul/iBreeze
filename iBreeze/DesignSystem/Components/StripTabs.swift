import SwiftUI

/// 顶部源标签条：图标 + 名称，横向滚动，选中项带下划线
struct SourceTabStrip: View {
    let sources: [InstalledPlugin]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(sources) { source in
                    button(for: source)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.page)
        }
    }

    private func button(for source: InstalledPlugin) -> some View {
        let isSelected = selection == source.uuid

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selection = source.uuid }
        } label: {
            VStack(spacing: 5) {
                PluginIconImage(url: source.iconURL)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(source.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)

                Capsule()
                    .fill(isSelected ? Color.accentColor : .clear)
                    .frame(height: 2)
            }
            .frame(minWidth: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(source.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// 入口筛选条：插件声明的多个入口（最新 / 热门 / 排行…）
struct EntryPillStrip: View {
    let entries: [PluginFunctionItem]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(entries) { entry in
                    pill(for: entry)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.page)
        }
    }

    private func pill(for entry: PluginFunctionItem) -> some View {
        let isSelected = selection == entry.id

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selection = entry.id }
        } label: {
            Text(entry.title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.18) : Color(uiColor: .tertiarySystemFill))
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
