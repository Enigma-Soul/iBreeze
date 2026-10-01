import Observation

/// 谁需要重新登录。
///
/// 插件的任意一次调用都可能报「未授权」（列表、详情、取图……），逐个页面处理
/// 不现实，所以由 `PluginRuntime` 统一上报到这里。
///
/// 上报后**不直接弹表单**：用户可能正在看漫画，整屏盖住太打断。先在右上角
/// 放一条带「登录」按钮的提示，点了才展开表单。
@MainActor
@Observable
final class PluginLoginCenter {
    static let shared = PluginLoginCenter()

    struct Request: Identifiable, Equatable {
        let pluginID: String
        let pluginName: String
        let message: String
        var id: String { pluginID }
    }

    /// 可写：根视图拿它当 `.sheet(item:)` 的绑定，关掉时由系统置空
    var request: Request?

    /// 从任意线程上报
    nonisolated static func report(pluginID: String, message: String = "登录已过期，请重新登录") {
        Task { @MainActor in
            shared.notify(pluginID: pluginID, message: message)
        }
    }

    /// 只发提示，不弹表单
    func notify(pluginID: String, message: String) {
        let name = PluginRegistry.shared.plugin(uuid: pluginID)?.name ?? pluginID
        ToastCenter.shared.show("\(name)：\(message)", actionTitle: "登录") { [weak self] in
            self?.present(pluginID: pluginID, message: message)
        }
    }

    /// 展开登录表单（用户点了提示上的按钮，或从插件设置里主动进入）
    func present(pluginID: String, message: String = "") {
        request = Request(
            pluginID: pluginID,
            pluginName: PluginRegistry.shared.plugin(uuid: pluginID)?.name ?? pluginID,
            message: message
        )
    }

    func dismiss() {
        request = nil
    }
}
