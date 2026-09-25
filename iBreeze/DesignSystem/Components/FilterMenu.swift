import SwiftUI

/// 列表筛选入口：把插件声明的筛选项做成菜单，选中项显示在按钮上
struct FilterMenu: View {
    let title: String?
    let options: [FilterBundle.Option]
    let activeLabel: String?
    let onSelect: (FilterBundle.Option) -> Void

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button(option.label) { onSelect(option) }
            }
        } label: {
            Label(activeLabel ?? title ?? "筛选", systemImage: "line.3.horizontal.decrease.circle")
                .font(.footnote)
        }
        .accessibilityLabel("筛选")
    }
}
