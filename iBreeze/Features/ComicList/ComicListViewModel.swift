import Foundation
import Observation

/// 插件定义的列表页：按 `fnPath` 分页取数，并支持插件声明的筛选器
@MainActor
@Observable
final class ComicListViewModel {
    private(set) var items: [ComicListItem] = []
    private(set) var isLoading = false
    private(set) var hasReachedMax = false
    private(set) var errorMessage: String?

    /// 插件声明的筛选项（排行榜的时间范围之类）
    private(set) var filterOptions: [FilterBundle.Option] = []
    private(set) var filterTitle: String?
    private(set) var activeFilterLabel: String?

    private let sourceID: String
    private let fnPath: String
    private let baseCore: JSONValue?
    private let baseExtern: JSONValue?
    private let filterFnPath: String?

    private var selectedFilterResult: FilterBundle.Option.Result?
    private var loadedPages = 0

    init(
        sourceID: String,
        fnPath: String,
        core: JSONValue?,
        extern: JSONValue?,
        filterFnPath: String? = nil
    ) {
        self.sourceID = sourceID
        self.fnPath = fnPath
        self.baseCore = core
        self.baseExtern = extern
        self.filterFnPath = filterFnPath
    }

    var hasFilter: Bool { !filterOptions.isEmpty }

    func refresh() async {
        items = []
        loadedPages = 0
        hasReachedMax = false
        errorMessage = nil
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, !hasReachedMax else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let source = try await PluginRegistry.shared.source(for: sourceID)
            let result = try await source.pagedList(
                fnPath: fnPath,
                page: loadedPages + 1,
                core: mergedCore,
                extern: mergedExtern
            )
            loadedPages += 1
            items.append(contentsOf: result.resolvedItems)
            hasReachedMax = result.resolvedHasReachedMax
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 拉取筛选器，页面出现时调一次
    func loadFilterIfNeeded() async {
        guard let filterFnPath, filterOptions.isEmpty else { return }

        do {
            let source = try await PluginRegistry.shared.source(for: sourceID)
            let bundle = try await source.filterBundle(fnPath: filterFnPath)
            filterTitle = bundle.primaryField?.label ?? bundle.scheme?.title
            filterOptions = bundle.primaryField?.options ?? []
        } catch {
            // 筛选器拿不到不影响列表本身
            filterOptions = []
        }
    }

    /// 选中一个筛选项：合并它的请求参数并重新加载
    func apply(option: FilterBundle.Option) async {
        activeFilterLabel = option.label
        selectedFilterResult = option.result
        await refresh()
    }

    private var mergedCore: JSONValue? {
        merge(baseCore, selectedFilterResult?.core)
    }

    private var mergedExtern: JSONValue? {
        merge(baseExtern, selectedFilterResult?.extern)
    }

    private func merge(_ base: JSONValue?, _ extra: JSONValue?) -> JSONValue? {
        guard case .object(let extras)? = extra else { return base }
        guard case .object(let originals)? = base else { return extra }
        return .object(originals.merging(extras) { _, new in new })
    }
}
