import Foundation
import Observation

/// 一条浏览记录
struct ReadingHistoryEntry: Codable, Hashable, Identifiable, Sendable {
    var source: String
    var comicID: String
    var title: String
    var coverURL: String?
    var chapterID: String?
    var chapterName: String?
    var updatedAt: Date

    var id: String { "\(source)#\(comicID)" }
}

/// 浏览记录：最近读的在前，最多保留 100 条
@MainActor
@Observable
final class ReadingHistoryStore {
    static let shared = ReadingHistoryStore()

    private static let limit = 100

    private(set) var entries: [ReadingHistoryEntry]

    private let file = JSONFileStore(filename: "reading-history.json", default: [ReadingHistoryEntry]())

    init() {
        entries = file.read()
    }

    func record(_ entry: ReadingHistoryEntry) {
        file.update { list in
            list.removeAll { $0.id == entry.id }
            list.insert(entry, at: 0)
            if list.count > Self.limit {
                list.removeLast(list.count - Self.limit)
            }
        }
        entries = file.read()
    }

    func remove(_ entry: ReadingHistoryEntry) {
        file.update { list in
            list.removeAll { $0.id == entry.id }
        }
        entries = file.read()
    }

    func clear() {
        file.update { $0.removeAll() }
        entries = []
    }
}
