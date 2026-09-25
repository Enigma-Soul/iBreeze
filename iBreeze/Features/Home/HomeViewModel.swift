import Foundation
import Observation

/// 首页 VM：把已安装插件当作数据源，切换源与入口并加载对应列表。
///
/// 结构参照 EhViewer：首页、搜索、收藏其实是同一个列表容器换数据源，
/// 顶部只负责切换「看哪个源、看哪个入口」。
@MainActor
@Observable
final class HomeViewModel {
    private(set) var sources: [InstalledPlugin] = []
    private(set) var entries: [PluginFunctionItem] = []
    private(set) var list: ComicListViewModel?

    var selectedSourceID: String?
    var selectedEntryID: String?

    private var registry: PluginRegistry { .shared }

    /// 当前源没有浏览入口时，只能靠搜索（不少插件是这种）
    var selectedSourceNeedsSearch: Bool {
        selectedSourceID != nil && entries.isEmpty
    }

    var selectedSource: InstalledPlugin? {
        sources.first { $0.uuid == selectedSourceID }
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
        await loadList()
    }

    /// 取当前源的浏览入口
    private func loadEntries() async {
        list = nil
        entries = []
        selectedEntryID = nil

        guard let source = sources.first(where: { $0.uuid == selectedSourceID }) else { return }
        entries = source.functions.filter { $0.action.type == "openComicList" && $0.action.payload?.scene != nil }

        guard let first = entries.first else { return }
        selectedEntryID = first.id
        await loadList()
    }

    private func loadList() async {
        guard
            let sourceID = selectedSourceID,
            let entry = entries.first(where: { $0.id == selectedEntryID }),
            let scene = entry.action.payload?.scene
        else {
            list = nil
            return
        }

        let viewModel = ComicListViewModel(
            sourceID: sourceID,
            fnPath: scene.body.request.fnPath,
            core: scene.body.request.core,
            extern: scene.body.request.extern
        )
        list = viewModel
        await viewModel.loadMore()
    }
}
