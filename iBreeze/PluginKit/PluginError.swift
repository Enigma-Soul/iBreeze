import Foundation

/// 插件运行时错误
enum PluginError: LocalizedError, Equatable {
    /// 无法创建 JavaScript 运行时
    case runtimeUnavailable
    /// 尚未加载插件 bundle
    case runtimeNotLoaded
    /// 插件自身抛出的错误
    case pluginThrew(String)
    /// 宿主未实现该路由
    case unsupportedRoute(String)
    /// 入参不合法
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable: "无法创建 JavaScript 运行时"
        case .runtimeNotLoaded: "插件尚未加载"
        case .pluginThrew(let message): message
        case .unsupportedRoute(let route): "宿主未实现路由：\(route)"
        case .invalidPayload(let detail): "插件入参不合法：\(detail)"
        }
    }
}
