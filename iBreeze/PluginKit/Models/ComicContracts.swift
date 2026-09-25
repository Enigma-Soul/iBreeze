import Foundation

/// 图片项。`url` 由插件自行用于下载，宿主只做格式校验
struct ImageItem: Codable, Hashable, Sendable {
    var id: String?
    var url: String?
    var name: String?
    var path: String?
    var extern: JSONValue?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenientString(forKey: .id)
        url = container.lenientString(forKey: .url)
        name = container.lenientString(forKey: .name)
        path = container.lenientString(forKey: .path)
        extern = container.lenientObject(JSONValue.self, forKey: .extern)
    }
}

/// 分页信息
struct PagingInfo: Codable, Hashable, Sendable {
    var page: Int?
    var pages: Int?
    var total: Int?
    var hasReachedMax: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        page = container.lenientInt(forKey: .page)
        pages = container.lenientInt(forKey: .pages)
        total = container.lenientInt(forKey: .total)
        hasReachedMax = container.lenientBool(forKey: .hasReachedMax)
    }
}

/// 详情页可点击的元信息
struct ActionItem: Codable, Hashable, Sendable {
    var name: String?
    var onTap: JSONValue?
    var extern: JSONValue?
}

/// 列表条目的元信息（作者、标签等）
struct MetadataListItem: Codable, Hashable, Sendable {
    var type: String?
    var name: String?
    var value: [ActionItem]?
}

/// 漫画列表条目
struct ComicListItem: Codable, Hashable, Identifiable, Sendable {
    var source: String?
    var id: String
    var title: String
    var subtitle: String?
    var finished: Bool?
    var likesCount: Int?
    var viewsCount: Int?
    var updatedAt: String?
    var cover: ImageItem?
    var metadata: [MetadataListItem]?
    var raw: JSONValue?
    var extern: JSONValue?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        guard let id = container.lenientString(forKey: .id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "列表条目缺少 id")
        }
        guard let title = container.lenientString(forKey: .title) else {
            throw DecodingError.dataCorruptedError(forKey: .title, in: container, debugDescription: "列表条目缺少标题")
        }

        self.id = id
        self.title = title
        source = container.lenientString(forKey: .source)
        subtitle = container.lenientString(forKey: .subtitle)
        finished = container.lenientBool(forKey: .finished)
        likesCount = container.lenientInt(forKey: .likesCount)
        viewsCount = container.lenientInt(forKey: .viewsCount)
        updatedAt = container.lenientString(forKey: .updatedAt)
        cover = container.lenientObject(ImageItem.self, forKey: .cover)
        metadata = container.lenientObject([MetadataListItem].self, forKey: .metadata)
        raw = container.lenientObject(JSONValue.self, forKey: .raw)
        extern = container.lenientObject(JSONValue.self, forKey: .extern)
    }
}

/// 搜索 / 列表结果：顶层与 data 内都可能有 items，取到哪个用哪个
struct ComicPagedList: Codable, Hashable, Sendable {
    var source: String?
    var extern: JSONValue?
    var items: [ComicListItem]?
    var paging: PagingInfo?
    var hasReachedMax: Bool?
    var data: Payload?

    struct Payload: Codable, Hashable, Sendable {
        var items: [ComicListItem]?
        var paging: PagingInfo?
        var hasReachedMax: Bool?
    }

    var resolvedItems: [ComicListItem] { items ?? data?.items ?? [] }
    var resolvedPaging: PagingInfo? { paging ?? data?.paging }
    var resolvedHasReachedMax: Bool {
        hasReachedMax ?? data?.hasReachedMax ?? resolvedPaging?.hasReachedMax ?? false
    }
}

/// 章节摘要
struct ChapterSummary: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var requestId: String?
    var logicalKey: String?
    var storageChapterId: String?
    var name: String?
    var order: Int?
    var extern: JSONValue?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.lenientString(forKey: .id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "章节缺少 id")
        }
        self.id = id
        requestId = container.lenientString(forKey: .requestId)
        logicalKey = container.lenientString(forKey: .logicalKey)
        storageChapterId = container.lenientString(forKey: .storageChapterId)
        name = container.lenientString(forKey: .name)
        order = container.lenientInt(forKey: .order)
        extern = container.lenientObject(JSONValue.self, forKey: .extern)
    }

    /// 宿主请求章节时使用 requestId，缺失时退回章节自身 id
    var resolvedRequestId: String { requestId ?? id }
}

/// 章节内的一页
struct ChapterPage: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String?
    var path: String?
    var url: String?
    var extern: JSONValue?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.lenientString(forKey: .id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "页面缺少 id")
        }
        self.id = id
        name = container.lenientString(forKey: .name)
        path = container.lenientString(forKey: .path)
        url = container.lenientString(forKey: .url)
        extern = container.lenientObject(JSONValue.self, forKey: .extern)
    }
}

/// 章节 + 图片列表
struct ChapterWithPages: Codable, Hashable, Sendable {
    var id: String?
    var name: String?
    var order: Int?
    var pages: [ChapterPage]?
    var extern: JSONValue?
}

/// 详情页数据
struct ComicDetailResult: Codable, Hashable, Sendable {
    var source: String?
    var comicId: String?
    var extern: JSONValue?
    var data: Payload?

    struct Payload: Codable, Hashable, Sendable {
        var normal: Normal?
        var raw: JSONValue?
    }

    struct Normal: Codable, Hashable, Sendable {
        var comicInfo: ComicInfo?
        var preview: Preview?
        var eps: [ChapterSummary]?
        var recommend: [ComicListItem]?
        var totalViews: Int?
        var totalLikes: Int?
        var totalComments: Int?
        var isFavourite: Bool?
        var isLiked: Bool?
        var allowComments: Bool?
        var allowLike: Bool?
        var allowCollected: Bool?
        var allowDownload: Bool?
        var extern: JSONValue?
    }

    struct ComicInfo: Codable, Hashable, Sendable {
        var id: String?
        var title: String?
        var titleMeta: [ActionItem]?
        var creator: Creator?
        var description: String?
        var cover: ImageItem?
        var metadata: [MetadataListItem]?
        var extern: JSONValue?

        struct Creator: Codable, Hashable, Sendable {
            var id: String?
            var name: String?
            var avatar: ImageItem?
            var extern: JSONValue?
        }
    }

    struct Preview: Codable, Hashable, Sendable {
        var enabled: Bool?
        var extern: JSONValue?
    }
}

/// 阅读快照：阅读页初始化或切章时获取
struct ReadSnapshot: Codable, Hashable, Sendable {
    var source: String?
    var extern: JSONValue?
    var data: Payload?

    struct Payload: Codable, Hashable, Sendable {
        var comic: Comic?
        var chapter: ChapterWithPages?
        var chapters: [ChapterSummary]?
    }

    struct Comic: Codable, Hashable, Sendable {
        var id: String?
        var source: String?
        var title: String?
        var extern: JSONValue?
    }
}
