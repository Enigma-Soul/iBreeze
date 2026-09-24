import SwiftUI

/// App 内导航路由：所有页面跳转都走这里，便于集中管理
enum AppRoute: Hashable {
    /// 插件定义的列表页（按 source + fnPath 取数）
    case comicList(sourceID: String, fnPath: String, title: String, core: JSONValue?, extern: JSONValue?)
    /// 漫画详情
    case comicDetail(sourceID: String, comicID: String)
    /// 阅读页
    case reader(sourceID: String, comicID: String, chapterID: String, chapterName: String, title: String)
}

extension View {
    /// 统一注册路由目的地
    func appNavigationDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .comicList(let sourceID, let fnPath, let title, let core, let extern):
                ComicListPage(sourceID: sourceID, fnPath: fnPath, title: title, core: core, extern: extern)

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
            }
        }
    }
}
