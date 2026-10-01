import Foundation

/// 列表筛选器（`scene.filter.fnPath` → `getRankingFilterBundle` 等）。
///
/// 选中某个选项后，把它的 `result.core` / `result.extern` 合并进下一次列表请求。
struct FilterBundle: Decodable, Hashable, Sendable {
    var scheme: Scheme?
    var data: Payload?

    struct Scheme: Decodable, Hashable, Sendable {
        var title: String?
        var fields: [Field]?
    }

    struct Field: Decodable, Hashable, Sendable {
        var key: String
        var kind: String?
        var label: String?
        var options: [Option]?
    }

    struct Option: Decodable, Hashable, Sendable {
        var label: String
        var value: JSONValue?
        var result: Result?
        var children: [Option]?

        struct Result: Decodable, Hashable, Sendable {
            var core: JSONValue?
            var extern: JSONValue?
        }
    }

    struct Payload: Decodable, Hashable, Sendable {
        var values: JSONValue?
    }

    /// 第一个带选项的字段，够渲染一个筛选入口
    var primaryField: Field? {
        scheme?.fields?.first { !($0.options ?? []).isEmpty }
    }
}
