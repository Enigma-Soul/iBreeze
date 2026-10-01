import Foundation

/// 插件自定义页面（`openPluginFunction` → `getFunctionPage`）。
///
/// 页面本身是声明式的：`scheme.body` 描述结构，`data` 按 key 提供内容，
/// 宿主不需要理解业务就能渲染出来。
struct FunctionPage: Decodable, Hashable, Sendable {
    var source: String?
    var scheme: Scheme?
    var data: JSONValue?

    struct Scheme: Decodable, Hashable, Sendable {
        var title: String?
        var body: BodyNode?
    }

    /// 页面结构节点，可嵌套
    indirect enum BodyNode: Decodable, Hashable, Sendable {
        case list(children: [BodyNode])
        case chipList(key: String)
        case actionGrid(key: String)
        case comicSectionList(key: String)
        case comicGrid(key: String, title: String?)
        case unknown

        enum CodingKeys: String, CodingKey {
            case type
            case children
            case key
            case title
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""

            switch type {
            case "list":
                self = .list(children: try container.decodeIfPresent([BodyNode].self, forKey: .children) ?? [])
            case "chip-list":
                self = .chipList(key: try container.decodeIfPresent(String.self, forKey: .key) ?? "")
            case "action-grid":
                self = .actionGrid(key: try container.decodeIfPresent(String.self, forKey: .key) ?? "")
            case "comic-section-list":
                self = .comicSectionList(key: try container.decodeIfPresent(String.self, forKey: .key) ?? "")
            case "comic-grid":
                self = .comicGrid(
                    key: try container.decodeIfPresent(String.self, forKey: .key) ?? "",
                    title: try container.decodeIfPresent(String.self, forKey: .title)
                )
            default:
                self = .unknown
            }
        }
    }

    // MARK: - 数据取值

    /// chip-list 的内容
    func chips(for key: String) -> [ChipItem] {
        decode(key, as: ChipItem.self)
    }

    /// action-grid 的内容
    func actionGrid(for key: String) -> [GridItem] {
        decode(key, as: GridItem.self)
    }

    /// comic-grid 的内容
    func comics(for key: String) -> [ComicListItem] {
        decode(key, as: ComicListItem.self)
    }

    /// comic-section-list 的内容
    func sections(for key: String) -> [ComicSection] {
        decode(key, as: ComicSection.self)
    }

    private func decode<T: Decodable>(_ key: String, as type: T.Type) -> [T] {
        guard key.isEmpty == false, let container = data?[key] else { return [] }
        // data 可能是对象（按 key 索引），也可能是直接数组
        if case .array(let items) = container {
            return items.compactMap { Self.decodeItem($0, as: type) }
        }
        if case .object(let dictionary) = container, case .array(let items)? = dictionary["items"] {
            return items.compactMap { Self.decodeItem($0, as: type) }
        }
        return []
    }

    private static func decodeItem<T: Decodable>(_ value: JSONValue, as type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    struct ChipItem: Decodable, Hashable, Sendable {
        var label: String
        var action: PluginAction?
    }

    struct GridItem: Decodable, Hashable, Sendable {
        var title: String?
        var cover: ImageItem?
        var action: JSONValue?
    }

    struct ComicSection: Decodable, Hashable, Sendable {
        var title: String?
        var subtitle: String?
        var items: [ComicListItem]?
    }
}
