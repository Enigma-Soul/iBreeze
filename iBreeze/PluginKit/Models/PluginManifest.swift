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

/// 列表场景：宿主据此渲染列表页，并调用取数函数
///
/// 文档里的写法是 `body.request`，但禁漫等插件用的是 `list`，两种都要认。
struct ComicListScene: Codable, Hashable, Sendable {
    var title: String
    var source: String
    var body: Body?
    var list: Request?
    var filter: Request?

    /// 取数请求，兼容新旧两种写法
    var request: Request? { body?.request ?? list }

    /// 列表类型 + 取数请求
    struct Body: Codable, Hashable, Sendable {
        var type: String?
        var request: Request
    }

    struct Request: Codable, Hashable, Sendable {
        var fnPath: String
        var core: JSONValue?
        var extern: JSONValue?

        /// 把筛选器选中的 `result.core` / `result.extern` 合并进来
        func merging(core extraCore: JSONValue?, extern extraExtern: JSONValue?) -> Request {
            Request(
                fnPath: fnPath,
                core: Self.merge(core, with: extraCore),
                extern: Self.merge(extern, with: extraExtern)
            )
        }

        private static func merge(_ base: JSONValue?, with extra: JSONValue?) -> JSONValue? {
            guard case .object(let extras)? = extra else { return base }
            guard case .object(let originals)? = base else { return extra }
            return .object(originals.merging(extras) { _, new in new })
        }
    }
}
