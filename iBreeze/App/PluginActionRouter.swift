import Foundation

/// 把插件声明的 `action` 统一映射成 App 内路由。
///
/// 插件入口、功能页里的 chip 与卡片都走这里，避免每处各写一遍类型判断。
enum PluginActionRouter {
    static func route(for action: PluginAction, sourceID: String, sourceName: String) -> AppRoute? {
        switch action.type {
        case "openComicList":
            guard let scene = action.payload?.scene, let request = scene.request else { return nil }
            return .comicList(
                sourceID: sourceID,
                fnPath: request.fnPath,
                title: scene.title,
                core: request.core,
                extern: request.extern,
                filterFnPath: scene.filter?.fnPath
            )

        case "openComicDetail":
            guard let comicID = action.payload?.comicId, !comicID.isEmpty else { return nil }
            return .comicDetail(sourceID: sourceID, comicID: comicID)

        case "openPluginFunction":
            guard let id = action.payload?.id, !id.isEmpty else { return nil }
            return .functionPage(sourceID: sourceID, pageID: id, title: action.payload?.title ?? "")

        case "openSearch":
            return .pluginSearch(sourceID: sourceID, name: sourceName, keyword: action.payload?.keyword ?? "")

        default:
            return nil
        }
    }

    /// 功能页里的 `action` 是松散对象，这里尝试还原成 `PluginAction`
    static func action(from value: JSONValue?) -> PluginAction? {
        guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(PluginAction.self, from: data)
    }
}
