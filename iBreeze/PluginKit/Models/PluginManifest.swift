import Foundation

/// 插件清单（manifest.json / getInfo 返回），云端列表与本地安装共用
struct PluginManifest: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var uuid: String
    var iconUrl: String?
    var creator: Creator?
    var describe: String?
    var version: String?
    var home: String?
    var updateUrl: String?
    var npmName: String?
    var function: [PluginFunctionItem]?

    var id: String { uuid }

    struct Creator: Codable, Hashable, Sendable {
        var name: String?
        var describe: String?
        var coverUrl: String?
    }
}

/// 插件功能入口
struct PluginFunctionItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var action: PluginAction
}

/// 功能入口动作，`type` 决定 payload 的字段
struct PluginAction: Codable, Hashable, Sendable {
    var type: String
    var payload: Payload?

    struct Payload: Codable, Hashable, Sendable {
        var source: String?
        var keyword: String?
        var comicId: String?
        var title: String?
        var url: String?
        var id: String?
        var presentation: String?
        var scene: ComicListScene?
    }
}

/// 列表场景：宿主据此渲染列表页，并调用 `body.request.fnPath` 取数据
struct ComicListScene: Codable, Hashable, Sendable {
    var title: String
    var source: String
    var body: Request
    var filter: Request?

    struct Request: Codable, Hashable, Sendable {
        var fnPath: String
        var core: JSONValue?
        var extern: JSONValue?
    }
}
