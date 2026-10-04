import SwiftUI

/// 置顶搜索框，给插件内搜索页（`PluginSearchPage`）用。
///
/// 全局搜索已经交给系统的搜索标签（`.searchable` + `role: .search`，底栏直接变成
/// 搜索框）；插件内搜索是推进来的普通页面，标题就是插件名，再挂一次 `.searchable`
/// 会和标题抢位置，也不方便带关键词进来直接搜，所以这里仍自绘一个常驻输入框。
struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .focused($isFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    isFocused = false
                    onSubmit()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空输入")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
        .padding(.horizontal, AppTheme.Spacing.page)
        .padding(.vertical, 8)
    }
}
