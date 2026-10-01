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
    /// 运行时 JS 脚本缺失（打包问题）
    case missingRuntimeScript
    /// 插件要求先登录：`scheme` 是它声明的表单，`data` 是预填值
    case unauthorized(message: String, scheme: JSONValue?, data: JSONValue?)

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable: "无法创建 JavaScript 运行时"
        case .runtimeNotLoaded: "插件尚未加载"
        case .pluginThrew(let message): message
        case .unsupportedRoute(let route): "宿主未实现路由：\(route)"
        case .invalidPayload(let detail): "插件入参不合法：\(detail)"
        case .missingRuntimeScript: "插件运行时脚本缺失，请检查打包配置"
        case .unauthorized(let message, _, _): message
        }
    }
}

extension PluginError {
    /// 插件抛结构化错误时写的是 `Error(JSON.stringify(payload))`，而宿主收到的是
    /// 被 JS 垫片接上调用栈的字符串（后面跟着 ` {frame ← frame}`），所以要先把
    /// 第一个完整的 JSON 对象切出来再看。
    static func fromPluginPayload(_ payload: String) -> PluginError {
        guard let object = firstJSONObject(in: payload), isLoginChallenge(object) else {
            return .pluginThrew(payload)
        }

        return .unauthorized(
            message: object["message"]?.stringValue ?? "登录已过期，请重新登录",
            scheme: object["scheme"],
            data: object["data"]
        )
    }

    /// 认 `type: "unauthorized"`；有的插件不给 type，只看它带没带登录表单
    private static func isLoginChallenge(_ object: [String: JSONValue]) -> Bool {
        if object["type"]?.stringValue == "unauthorized" { return true }
        return object["scheme"]?["type"]?.stringValue == "login"
    }

    /// 扫描出第一个括号配平的 JSON 对象；不是 JSON 就返回 nil
    private static func firstJSONObject(in payload: String) -> [String: JSONValue]? {
        guard let start = payload.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var isEscaped = false
        var end: String.Index?
        var index = start

        while index < payload.endIndex {
            let character = payload[index]

            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    end = index
                    break
                }
            }

            index = payload.index(after: index)
        }

        guard let end, let data = String(payload[start...end]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: JSONValue].self, from: data)
    }
}
