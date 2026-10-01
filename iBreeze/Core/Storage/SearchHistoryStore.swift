import Foundation
import Observation

/// 搜索记录：最近用过的关键词，最新在前
@MainActor
@Observable
final class SearchHistoryStore {
    static let shared = SearchHistoryStore()

    private static let limit = 20

    private(set) var keywords: [String]

    private let file = JSONFileStore(filename: "search-history.json", default: [String]())

    init() {
        keywords = file.read()
    }

    func record(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        mutate { list in
            list.removeAll { $0 == trimmed }
            list.insert(trimmed, at: 0)
            if list.count > Self.limit {
                list.removeLast(list.count - Self.limit)
            }
        }
    }

    func remove(_ keyword: String) {
        mutate { $0.removeAll { $0 == keyword } }
    }

    func clear() {
        mutate { $0.removeAll() }
    }

    private func mutate(_ transform: (inout [String]) -> Void) {
        file.update(transform)
        keywords = file.read()
    }
}
