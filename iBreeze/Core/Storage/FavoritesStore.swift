import Foundation
import Observation

/// 一条本地收藏
struct FavoriteEntry: Codable, Hashable, Identifiable, Sendable {
    var source: String
    var comicID: String
    var title: String
    var coverURL: String?
    var addedAt: Date

    var id: String { "\(source)#\(comicID)" }
}

/// 本地收藏：最近收藏的在前
@MainActor
@Observable
final class FavoritesStore {
    static let shared = FavoritesStore()

    private(set) var entries: [FavoriteEntry]

    private let file = JSONFileStore(filename: "favorites.json", default: [FavoriteEntry]())

    init() {
        entries = file.read()
    }

    func contains(source: String, comicID: String) -> Bool {
        entries.contains { $0.source == source && $0.comicID == comicID }
    }

    func toggle(_ entry: FavoriteEntry) {
        if contains(source: entry.source, comicID: entry.comicID) {
            remove(source: entry.source, comicID: entry.comicID)
        } else {
            file.update { $0.insert(entry, at: 0) }
            entries = file.read()
        }
    }

    func remove(source: String, comicID: String) {
        file.update { list in
            list.removeAll { $0.source == source && $0.comicID == comicID }
        }
        entries = file.read()
    }
}
