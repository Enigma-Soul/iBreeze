import Foundation

/// 插件返回值的宽松解码。
///
/// 契约里写的是字符串/布尔，但插件实际常常给数字：id 是数字、时间戳是数字、
/// 布尔给 0/1、页码给 5.0。严格解码会直接抛「数据格式不对」，
/// 因此这些叶子类型统一用这组取值方法。
extension KeyedDecodingContainer {
    /// 数字与字符串都按字符串收；空串视作没有
    func lenientString(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key), !value.isEmpty {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return value == value.rounded() ? String(Int(value)) : String(value)
        }
        return nil
    }

    /// 整数也可能写成 5.0 或 "5"
    func lenientInt(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? decode(String.self, forKey: key) { return Int(value) }
        return nil
    }

    /// 布尔也可能写成 0/1
    func lenientBool(forKey key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? decode(String.self, forKey: key) { return ["true", "1", "yes"].contains(value.lowercased()) }
        return nil
    }

    /// 可选嵌套对象：解不出来就当没有，不让整个列表失败
    func lenientObject<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decode(type, forKey: key)
    }
}
