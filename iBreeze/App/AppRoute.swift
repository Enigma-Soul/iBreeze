import SwiftUI

/// App 内导航路由：所有页面跳转都走这里，便于集中管理
enum AppRoute: Hashable {
    /// 插件定义的列表页（按 source + fnPath 取数）
    case comicList(
        sourceID: String,
        fnPath: String,
        title: String,
        core: JSONValue?,
        extern: JSONValue?,
        filterFnPath: String?
    )
    /// 漫画详情
    case comicDetail(sourceID: String, comicID: String)
    /// 阅读页
    case reader(sourceID: String, comicID: String, chapterID: String, chapterName: String, title: String)
    /// 插件自定义页面
    case functionPage(sourceID: String, pageID: String, title: String)
    /// 在指定插件内搜索
    case pluginSearch(sourceID: String, name: String, keyword: String)
}

extension View {
    /// 统一注册路由目的地
    func appNavigationDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .comicList(let sourceID, let fnPath, let title, let core, let extern, let filterFnPath):
                ComicListPage(
                    sourceID: sourceID,
                    fnPath: fnPath,
                    title: title,
                    core: core,
                    extern: extern,
                    filterFnPath: filterFnPath
                )

            case .comicDetail(let sourceID, let comicID):
                ComicDetailPage(sourceID: sourceID, comicID: comicID)

            case .reader(let sourceID, let comicID, let chapterID, let chapterName, let title):
                ReaderPage(
                    sourceID: sourceID,
                    comicID: comicID,
                    chapterID: chapterID,
                    chapterName: chapterName,
                    comicTitle: title
                )

            case .functionPage(let sourceID, let pageID, let title):
                FunctionPageView(sourceID: sourceID, pageID: pageID, title: title)

            case .pluginSearch(let sourceID, let name, let keyword):
                PluginSearchPage(sourceID: sourceID, sourceName: name, initialKeyword: keyword)
            }
        }
    }
}
