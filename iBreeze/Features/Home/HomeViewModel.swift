import Foundation
import Observation

/// 首页 VM：把已安装插件当作数据源，切换源与入口并加载对应内容。
///
/// 结构参照 EhViewer：首页、搜索、收藏其实是同一个列表容器换数据源，
/// 顶部只负责切换「看哪个源、看哪个入口」。
@MainActor
@Observable
final class HomeViewModel {
    /// 当前入口对应的内容形态
    enum Content {
        case list(ComicListViewModel)
        /// 插件自定义页面：直接在首页渲染，不做跳转
        case page(FunctionPageViewModel)
        /// 仍需要跳转的入口（如跳去搜索）
        case route(title: String, route: AppRoute)
        case unsupported(String)
    }

    private(set) var sources: [InstalledPlugin] = []
    private(set) var entries: [PluginFunctionItem] = []
    private(set) var content: Content?

    var selectedSourceID: String?
    var selectedEntryID: String?

    private var registry: PluginRegistry { .shared }

    var selectedSource: InstalledPlugin? {
        sources.first { $0.uuid == selectedSourceID }
    }

    /// 当前源没有浏览入口时，只能靠搜索（不少插件是这种）
    var selectedSourceNeedsSearch: Bool {
        selectedSourceID != nil && entries.isEmpty
    }

    func reload() async {
        sources = registry.installed

        // 选中的源还在就保持不变，被卸载才回退到第一个
        if let selectedSourceID, sources.contains(where: { $0.uuid == selectedSourceID }) {
            return
        }
        selectedSourceID = sources.first?.uuid
        await loadEntries()
    }

    func select(sourceID: String) async {
        selectedSourceID = sourceID
        await loadEntries()
    }

    func select(entryID: String) async {
        guard selectedEntryID != entryID else { return }
        selectedEntryID = entryID
        await loadSelectedEntry()
    }

    /// 取当前源的入口。除列表外，插件还可能提供自定义页面、云端收藏等
    private func loadEntries() async {
        content = nil
        entries = []
        selectedEntryID = nil

        guard let source = selectedSource else { return }

        // 云端收藏要先问插件有没有实现，不然点了只会得到一句报错，等于死路
        let plugin = try? await registry.source(for: source.uuid)
        let supportsCloudFavorite = await plugin?.exportsFunction("getCloudFavoriteSceneBundle") ?? false

        entries = source.functions.filter { isSupported($0, supportsCloudFavorite: supportsCloudFavorite) }

        guard let first = entries.first else { return }
        selectedEntryID = first.id
        await loadSelectedEntry()
    }

    private func isSupported(_ entry: PluginFunctionItem, supportsCloudFavorite: Bool) -> Bool {
        switch entry.action.type {
        case "openComicList": entry.action.payload?.scene?.request != nil
        case "openPluginFunction": !(entry.action.payload?.id ?? "").isEmpty
        case "openCloudFavorite": supportsCloudFavorite
        default: false
        }
    }

    private func loadSelectedEntry() async {
        content = nil

        guard let sourceID = selectedSourceID,
              let entry = entries.first(where: { $0.id == selectedEntryID })
        else { return }

        switch entry.action.type {
        case "openComicList":
            guard let scene = entry.action.payload?.scene, let request = scene.request else {
                content = .unsupported("该入口没有取数信息")
                return
            }
            await showList(scene: scene, request: request, sourceID: sourceID)

        case "openPluginFunction":
            guard let pageID = entry.action.payload?.id, !pageID.isEmpty else {
                content = .unsupported("「\(entry.title)」缺少页面标识")
                return
            }
            let page = FunctionPageViewModel(sourceID: sourceID, pageID: pageID, title: entry.title)
            content = .page(page)
            await page.load()

        case "openCloudFavorite":
            // 场景由宿主按契约去问插件要，结构与列表入口同源，所以能直接复用列表
            do {
                let source = try await registry.source(for: sourceID)
                let scene = try await source.cloudFavoriteScene()
                guard let request = scene.request else {
                    content = .unsupported("云端收藏没有提供取数信息")
                    return
                }
                await showList(scene: scene, request: request, sourceID: sourceID)
            } catch {
                content = .unsupported(error.localizedDescription)
            }

        default:
            content = .unsupported("暂不支持的入口：\(entry.action.type)")
        }
    }

    private func showList(scene: ComicListScene, request: ComicListScene.Request, sourceID: String) async {
        let list = ComicListViewModel(
            sourceID: sourceID,
            fnPath: request.fnPath,
            core: request.core,
            extern: request.extern,
            filterFnPath: scene.filter?.fnPath,
            filterCore: scene.filter?.core,
            filterExtern: scene.filter?.extern
        )
        content = .list(list)

        await list.loadFilterIfNeeded()
        await list.loadMore()
    }
}
