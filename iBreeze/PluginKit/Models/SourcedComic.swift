import Foundation

/// 列表条目 + 它来自哪个插件。
///
/// 契约里的 `ComicListItem.source` 是插件自己起的名字（e-hentai 写的是
/// `"ehentai"`），不是插件 uuid，拿它去查插件会找不到；全局搜索又需要区分
/// 每个条目属于哪个插件，所以由宿主在合并结果时记下来。
struct SourcedComic: Identifiable, Hashable {
    let item: ComicListItem
    let sourceID: String

    var id: String { "\(sourceID)#\(item.id)" }
}

extension ComicListItem {
    /// 补上宿主侧的来源插件
    func sourced(from sourceID: String) -> SourcedComic {
        SourcedComic(item: self, sourceID: sourceID)
    }
}
