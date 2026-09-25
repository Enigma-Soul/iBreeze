import Foundation
import Observation

/// 搜索页 VM：默认在所有插件里搜，也可以只搜某一个
@MainActor
@Observable
final class SearchViewModel {
    var keyword = ""
    /// nil 表示搜全部插件
    var selectedSourceID: String?

    private(set) var items: [ComicListItem] = []
    private(set) var isLoading = false
    private(set) var hasReachedMax = false
    private(set) var errorMessage: String?

    private var loadedPages = 0

    /// 本次搜索命中的插件，用于翻页
    private var searchedSourceIDs: [String] = []

    /// 在选中范围内搜索（首页/重置用）
    func search(sourceIDs: [String]) async {
        items = []
        loadedPages = 0
        hasReachedMax = false
        errorMessage = nil
        searchedSourceIDs = sourceIDs

        SearchHistoryStore.shared.record(keyword)
        await loadMore()
    }

    func search(sourceID: String) async {
        await search(sourceIDs: [sourceID])
    }

    func loadMore() async {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading, !hasReachedMax, !searchedSourceIDs.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        let page = loadedPages + 1
        var collected: [ComicListItem] = []
        var failures: [String] = []

        // 全局搜索时各插件并发查，谁先回来都行
        await withTaskGroup(of: Result<ComicPagedList, Error>.self) { group in
            for sourceID in searchedSourceIDs {
                group.addTask { [text, page] in
                    do {
                        let source = try await PluginRegistry.shared.source(for: sourceID)
                        return .success(try await source.pagedList(fnPath: "searchComic", page: page, keyword: text))
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for await result in group {
                switch result {
                case .success(let list):
                    collected.append(contentsOf: list.resolvedItems)
                    // 任一插件到底就算到底
                    if list.resolvedHasReachedMax { hasReachedMax = true }
                case .failure(let error):
                    failures.append(error.localizedDescription)
                }
            }
        }

        loadedPages = page
        items.append(contentsOf: collected)

        // 全失败才提示，部分失败不影响结果展示
        if collected.isEmpty, !failures.isEmpty, items.isEmpty {
            errorMessage = failures.first
        }
        if collected.isEmpty, failures.isEmpty {
            hasReachedMax = true
        }
        if searchedSourceIDs.count > 1, items.count > 0, collected.isEmpty {
            hasReachedMax = true
        }
    }
}
