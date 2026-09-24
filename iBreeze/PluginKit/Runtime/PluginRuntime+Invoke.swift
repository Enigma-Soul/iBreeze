import Foundation

extension PluginRuntime {
    /// 调用 `fnPath` 并把结果解码为指定类型
    func invoke<T: Decodable>(_ type: T.Type, fnPath: String, payloadJSON: String = "{}") async throws -> T {
        let json = try await invoke(fnPath: fnPath, payloadJSON: payloadJSON)
        guard let data = json.data(using: .utf8) else {
            throw PluginError.invalidPayload("插件返回值不是合法 UTF-8")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
