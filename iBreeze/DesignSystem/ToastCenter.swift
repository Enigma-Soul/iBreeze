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

    /// 带动作的提示留久一点，免得不小心划过去
    private static let plainDuration: TimeInterval = 3
    private static let actionDuration: TimeInterval = 6

    func show(
        _ message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        // 同一条消息不叠第二条：登录过期时并发取图会一次炸出七八个
        if let existing = toasts.first(where: { $0.message == message }) {
            scheduleDismissal(existing.id, after: duration(for: existing))
            return
        }

        let toast = Toast(message: message, actionTitle: actionTitle, action: action)
        toasts.append(toast)
        scheduleDismissal(toast.id, after: duration(for: toast))
    }

    func dismiss(_ id: UUID) {
        dismissals[id]?.cancel()
        dismissals[id] = nil
        toasts.removeAll { $0.id == id }
    }

    private func duration(for toast: Toast) -> TimeInterval {
        toast.actionTitle == nil ? Self.plainDuration : Self.actionDuration
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
