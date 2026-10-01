import SwiftUI

/// 把 `ToastCenter` 里的提示叠在右上角
struct ToastHost: View {
    private let center = ToastCenter.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(center.toasts) { toast in
                ToastBanner(toast: toast) { center.dismiss(toast.id) }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, AppTheme.Spacing.page)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.snappy(duration: 0.25), value: center.toasts.map(\.id))
        // 没有提示时完全不吃触摸，别挡住下面的返回键之类
        .allowsHitTesting(!center.toasts.isEmpty)
    }
}

private struct ToastBanner: View {
    let toast: ToastCenter.Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(toast.message.convertedChinese)
                .font(.subheadline)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            if let actionTitle = toast.actionTitle {
                Button(actionTitle) {
                    toast.action?()
                    onDismiss()
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .frame(maxWidth: 320, alignment: .trailing)
    }
}
