import Observation

/// 谁需要重新登录。
///
/// 插件的任意一次调用都可能报「未授权」（列表、详情、取图……），逐个页面处理
/// 不现实，所以由 `PluginRuntime` 统一上报到这里，根视图只认这一个入口。
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

    /// 从任意线程上报；重复上报同一个插件会被忽略，避免连点几次弹几张表
    nonisolated static func report(pluginID: String, message: String = "登录状态已失效，请重新登录") {
        Task { @MainActor in
            shared.present(pluginID: pluginID, message: message)
        }
    }

    func present(pluginID: String, message: String) {
        guard request?.pluginID != pluginID else { return }

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
