import Foundation

/// 单个插件源的会话：持有常驻运行时，把契约调用包成强类型方法。
///
/// 方法名与 Breeze 的 `fnPath` 一一对应，参数拼装规则也一致：
/// 业务参数放顶层，透传上下文放 `extern`。
final class PluginSource: @unchecked Sendable {
    let plugin: InstalledPlugin
    private let runtime: PluginRuntime

    init(plugin: InstalledPlugin) {
        self.plugin = plugin
        let pluginID = plugin.uuid
        runtime = PluginRuntime(pluginID: pluginID, host: PluginHostBridge(pluginID: pluginID))
    }

    /// 载入 bundle（重建运行时后模块级状态不保留）
    func load(bundle: String) async throws {
        try await runtime.load(bundle: bundle)
    }

    func shutdown() async {
        await runtime.shutdown()
    }

    // MARK: - 核心契约

    func info() async throws -> PluginManifest {
        try await runtime.invoke(PluginManifest.self, fnPath: "getInfo")
    }

    /// 搜索 / 列表统一入口：`fnPath` 由插件的方案决定
    func pagedList(
        fnPath: String,
        page: Int? = nil,
        keyword: String? = nil,
        core: JSONValue? = nil,
        extern: JSONValue? = nil
    ) async throws -> ComicPagedList {
        var payload = (core?.anyValue as? [String: Any]) ?? [:]
        if let page { payload["page"] = page }
        if let keyword { payload["keyword"] = keyword }
        payload["extern"] = extern?.anyValue ?? [:]

        return try await runtime.invoke(
            ComicPagedList.self,
            fnPath: fnPath,
            payloadJSON: try Self.json(payload)
        )
    }

    func comicDetail(comicID: String, extern: JSONValue? = nil) async throws -> ComicDetailResult {
        try await runtime.invoke(
            ComicDetailResult.self,
            fnPath: "getComicDetail",
            payloadJSON: try Self.json(["comicId": comicID, "extern": extern?.anyValue ?? [:]])
        )
    }

    func readSnapshot(comicID: String, chapterID: String, extern: JSONValue? = nil) async throws -> ReadSnapshot {
        try await runtime.invoke(
            ReadSnapshot.self,
            fnPath: "getReadSnapshot",
            payloadJSON: try Self.json([
                "comicId": comicID,
                "chapterId": chapterID,
                "extern": extern?.anyValue ?? [:]
            ])
        )
    }

    /// 图片下载：插件自己决定怎么拿，宿主只负责调度
    func imageBytes(url: String, timeoutMs: Int = 30_000, taskGroupKey: String = "") async throws -> Data {
        try await runtime.invokeData(
            fnPath: "fetchImageBytes",
            payloadJSON: try Self.json([
                "url": url,
                "timeoutMs": timeoutMs,
                "taskGroupKey": taskGroupKey
            ])
        )
    }

    // MARK: - 可选契约

    /// 发现页默认列表场景
    func sceneBundle() async throws -> JSONValue {
        try await invokeJSON(fnPath: "getComicListSceneBundle")
    }

    /// 插件自定义页面（`openPluginFunction` 的落地页）
    func functionPage(id: String, page: Int? = nil) async throws -> FunctionPage {
        var payload: [String: Any] = ["id": id]
        if let page { payload["page"] = page }

        let json = try await runtime.invoke(fnPath: "getFunctionPage", payloadJSON: try Self.json(payload))
        guard let data = json.data(using: .utf8) else {
            throw PluginError.invalidPayload("功能页返回值不是合法 UTF-8")
        }
        return try JSONDecoder().decode(FunctionPage.self, from: data)
    }

    /// 列表筛选器
    func filterBundle(fnPath: String) async throws -> FilterBundle {
        let json = try await runtime.invoke(fnPath: fnPath)
        guard let data = json.data(using: .utf8) else {
            throw PluginError.invalidPayload("筛选器返回值不是合法 UTF-8")
        }
        return try JSONDecoder().decode(FilterBundle.self, from: data)
    }

    /// 高级搜索筛选项
    func advancedSearch() async throws -> JSONValue {
        try await invokeJSON(fnPath: "getAdvancedSearchScheme")
    }

    /// 列表筛选器
    func filterBundle(fnPath: String) async throws -> JSONValue {
        try await invokeJSON(fnPath: fnPath)
    }

    /// 插件设置页
    func settingsBundle() async throws -> JSONValue {
        try await invokeJSON(fnPath: "getSettingsBundle")
    }

    /// 收藏工作流（`phase` 取 `start` / `continue`）
    func favoriteAction(phase: String, payload: JSONValue) async throws -> JSONValue {
        try await invokeJSON(
            fnPath: phase == "start" ? "startFavoriteAction" : "continueFavoriteAction",
            payloadJSON: try Self.json(payload.anyValue as? [String: Any] ?? [:])
        )
    }

    /// 收藏切换（旧协议，仍然被多数插件实现）
    func toggleFavorite(comicID: String, current: Bool, extern: JSONValue? = nil) async throws -> JSONValue {
        try await invokeJSON(
            fnPath: "toggleFavorite",
            payloadJSON: try Self.json([
                "comicId": comicID,
                "currentFavorite": current,
                "extern": extern?.anyValue ?? [:]
            ])
        )
    }

    /// 持久化插件设置项：与插件自己调 `pluginConfig.save` 写到同一份存储
    func saveSetting(key: String, value: JSONValue) async throws {
        let encoded = try Self.json(value.anyValue)
        _ = try await runtime.callHost(route: "save_plugin_config", args: [key, encoded])
    }

    /// 通知插件某个设置项变了，插件可在回调里做校验或联动
    func notifySettingChanged(fnPath: String, key: String, value: JSONValue) async throws {
        _ = try await invokeJSON(
            fnPath: fnPath,
            payloadJSON: try Self.json(["extern": [:], "key": key, "value": value.anyValue])
        )
    }

    // MARK: - 内部辅助

    /// 调用并解成 JSONValue，避免 `[String: Any]` 跨隔离边界
    private func invokeJSON(fnPath: String, payloadJSON: String = "{}") async throws -> JSONValue {
        let json = try await runtime.invoke(fnPath: fnPath, payloadJSON: payloadJSON)
        guard let data = json.data(using: .utf8) else {
            throw PluginError.invalidPayload("插件返回值不是合法 UTF-8")
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func json(_ payload: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }
}
