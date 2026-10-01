import Foundation
import Observation

/// 右上角气泡：面向「做完了」「登录过期了」这类不需要打断操作的提示。
///
/// 之前这些一律用 alert / sheet，用户正在看漫画也会被整屏盖住；气泡只占一角，
/// 带动作按钮时点一下才展开真正的界面。
@MainActor
@Observable
final class ToastCenter {
    static let shared = ToastCenter()

    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let actionTitle: String?
        let action: (() -> Void)?
    }

    private(set) var toasts: [Toast] = []
    private var dismissals: [UUID: Task<Void, Never>] = [:]

    /// 每条最多留 3 秒，屏幕上最多同时两条——再多就只剩挡视线的份
    private static let duration: TimeInterval = 3
    private static let maxVisible = 2

    func show(
        _ message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        // 同一条消息不叠第二条：登录过期时并发取图会一次炸出七八个
        if let existing = toasts.first(where: { $0.message == message }) {
            scheduleDismissal(existing.id, after: Self.duration)
            return
        }

        // 满了就先把最旧的挤出去
        while toasts.count >= Self.maxVisible, let oldest = toasts.first {
            dismiss(oldest.id)
        }

        let toast = Toast(message: message, actionTitle: actionTitle, action: action)
        toasts.append(toast)
        scheduleDismissal(toast.id, after: Self.duration)
    }

    func dismiss(_ id: UUID) {
        dismissals[id]?.cancel()
        dismissals[id] = nil
        toasts.removeAll { $0.id == id }
    }

    private func scheduleDismissal(_ id: UUID, after seconds: TimeInterval) {
        dismissals[id]?.cancel()
        dismissals[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }
}
