import SwiftUI

/// 置顶搜索框。
///
/// 不用系统 `.searchable`：在带自绘底部标签栏的页面上，它会把搜索框放到屏幕底部，
/// 与浮条叠在一起点不到。
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
