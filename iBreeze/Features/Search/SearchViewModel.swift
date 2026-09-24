import Foundation
import Observation

/// 搜索页 VM：用选中插件的 `searchComic` 取结果
@MainActor
@Observable
final class SearchViewModel {
    var keyword = ""
    var selectedSourceID: String?

    private(set) var items: [ComicListItem] = []
    private(set) var isLoading = false
    private(set) var hasReachedMax = false
    private(set) var errorMessage: String?

    private var loadedPages = 0

    /// 选中插件；没有显式选择时用第一个已安装插件
    func resolvedSourceID(installed: [InstalledPlugin]) -> String? {
        if let selectedSourceID, installed.contains(where: { $0.uuid == selectedSourceID }) {
            return selectedSourceID
        }
        return installed.first?.uuid
    }

    func search(sourceID: String) async {
        items = []
        loadedPages = 0
        hasReachedMax = false
        errorMessage = nil
        await loadMore(sourceID: sourceID)
    }

    func loadMore(sourceID: String) async {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading, !hasReachedMax else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let source = try await PluginRegistry.shared.source(for: sourceID)
            let result = try await source.pagedList(
                fnPath: "searchComic",
                page: loadedPages + 1,
                keyword: text
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
