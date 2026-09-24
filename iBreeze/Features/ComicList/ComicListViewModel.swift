import Foundation
import Observation

/// 插件定义的列表页：按 `fnPath` 分页取数
@MainActor
@Observable
final class ComicListViewModel {
    private(set) var items: [ComicListItem] = []
    private(set) var isLoading = false
    private(set) var hasReachedMax = false
    private(set) var errorMessage: String?

    private let sourceID: String
    private let fnPath: String
    private let core: JSONValue?
    private let extern: JSONValue?
    private var loadedPages = 0

    init(sourceID: String, fnPath: String, core: JSONValue?, extern: JSONValue?) {
        self.sourceID = sourceID
        self.fnPath = fnPath
        self.core = core
        self.extern = extern
    }

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
                core: core,
                extern: extern
            )
            loadedPages += 1
            items.append(contentsOf: result.resolvedItems)
            hasReachedMax = result.resolvedHasReachedMax
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
