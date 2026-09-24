import Foundation

/// 加密路由：Breeze 的 `crypto.*` 异步路由与 `__crypto_*` 同步钩子的宿主实现。
///
/// 入参与返回完全对齐 Breeze 的 `dispatch_crypto_route`：
/// 字节数组进出、`*_hex` 走 UTF-8 字符串、`*_b64` 走 Base64 字符串。
enum PluginCryptoRoutes {
    /// 处理异步路由，返回 nil 表示不是加密路由
    static func dispatch(route: String, args: [Any]) throws -> String? {
        guard route.hasPrefix("crypto.") else { return nil }

        switch route {
        case "crypto.md5", "crypto.sha1", "crypto.sha256", "crypto.sha512":
            let digest = PluginCrypto.digest(try algorithm(route), try bytes(args, 0, "input"))
            return try encode(PluginCrypto.hex(digest))

        case "crypto.hmac_sha1", "crypto.hmac_sha256", "crypto.hmac_sha512":
            let mac = try PluginCrypto.hmac(
                try algorithm(route),
                key: try bytes(args, 0, "key"),
                data: try bytes(args, 1, "input")
            )
            return try encode(PluginCrypto.hex(mac))

        case "crypto.aes_ecb_pkcs7_encrypt", "crypto.aes_ecb_pkcs7_decrypt":
            return try encode(bytes: PluginCrypto.aes(
                .ecb,
                encrypt: route.hasSuffix("encrypt"),
                input: try bytes(args, 0, "input"),
                key: try bytes(args, 1, "key"),
                iv: nil,
                aad: nil
            ))

        case "crypto.aes_cbc_pkcs7_encrypt", "crypto.aes_cbc_pkcs7_decrypt":
            return try encode(bytes: PluginCrypto.aes(
                .cbc,
                encrypt: route.hasSuffix("encrypt"),
                input: try bytes(args, 0, "input"),
                key: try bytes(args, 1, "key"),
                iv: try bytes(args, 2, "iv"),
                aad: nil
            ))

        case "crypto.aes_gcm_encrypt", "crypto.aes_gcm_decrypt":
            return try encode(bytes: PluginCrypto.aes(
                .gcm,
                encrypt: route.hasSuffix("encrypt"),
                input: try bytes(args, 0, "input"),
                key: try bytes(args, 1, "key"),
                iv: try bytes(args, 2, "nonce"),
                aad: try optionalBytes(args, 3)
            ))

        // 以下为已废弃的兼容路由：入参是 UTF-8 字符串
        case "crypto.md5_hex", "crypto.sha1_hex", "crypto.sha256_hex", "crypto.sha512_hex":
            let digest = PluginCrypto.digest(try algorithm(route), Data(try text(args, 0, "input").utf8))
            return try encode(PluginCrypto.hex(digest))

        case "crypto.hmac_sha1_hex", "crypto.hmac_sha256_hex", "crypto.hmac_sha512_hex":
            let mac = try PluginCrypto.hmac(
                try algorithm(route),
                key: Data(try text(args, 0, "key").utf8),
                data: Data(try text(args, 1, "input").utf8)
            )
            return try encode(PluginCrypto.hex(mac))

        case "crypto.aes_ecb_pkcs7_decrypt_b64":
            let plain = try PluginCrypto.aes(
                .ecb,
                encrypt: false,
                input: try base64(args, 0, "payload"),
                key: Data(try text(args, 1, "key").utf8),
                iv: nil,
                aad: nil
            )
            guard let plaintext = String(data: plain, encoding: .utf8) else {
                throw PluginCrypto.CryptoError.decryptionFailed
            }
            return try encode(plaintext)

        case "crypto.aes_cbc_pkcs7_encrypt_b64", "crypto.aes_cbc_pkcs7_decrypt_b64":
            let result = try PluginCrypto.aes(
                .cbc,
                encrypt: route.contains("_encrypt_"),
                input: try base64(args, 0, "payload"),
                key: Data(try text(args, 1, "key").utf8),
                iv: Data(try text(args, 2, "iv").utf8),
                aad: nil
            )
            return try encode(result.base64EncodedString())

        case "crypto.aes_gcm_encrypt_b64", "crypto.aes_gcm_decrypt_b64":
            let result = try PluginCrypto.aes(
                .gcm,
                encrypt: route.contains("_encrypt_"),
                input: try base64(args, 0, "payload"),
                key: Data(try text(args, 1, "key").utf8),
                iv: Data(try text(args, 2, "nonce").utf8),
                aad: args.indices.contains(3) ? try base64(args, 3, "aad") : nil
            )
            return try encode(result.base64EncodedString())

        default:
            throw PluginError.unsupportedRoute(route)
        }
    }

    /// 处理同步钩子（`__crypto_*`），返回 nil 表示不是加密钩子
    static func dispatchSync(route: String, args: [Any]) throws -> String? {
        guard route.hasPrefix("crypto."), route.hasSuffix("_bytes") || route == "crypto.random_uuid_v4" else {
            return nil
        }

        switch route {
        case "crypto.sha1_bytes", "crypto.sha256_bytes", "crypto.sha512_bytes":
            let digest = PluginCrypto.digest(try algorithm(route), try bytes(args, 0, "input"))
            return try encode(PluginCrypto.digestPayload(digest))

        case "crypto.hmac_sha1_bytes", "crypto.hmac_sha256_bytes", "crypto.hmac_sha512_bytes":
            let mac = try PluginCrypto.hmac(
                try algorithm(route),
                key: try bytes(args, 0, "key"),
                data: try bytes(args, 1, "input")
            )
            return try encode(PluginCrypto.digestPayload(mac))

        case "crypto.pbkdf2_sha256_bytes":
            let derived = try PluginCrypto.pbkdf2SHA256(
                password: try bytes(args, 0, "password"),
                salt: try bytes(args, 1, "salt"),
                rounds: try integer(args, 2, "iterations"),
                keyLength: try integer(args, 3, "keyLength")
            )
            return try encode(PluginCrypto.digestPayload(derived))

        case "crypto.aes_cbc_pkcs7_encrypt_bytes", "crypto.aes_cbc_pkcs7_decrypt_bytes":
            let result = try PluginCrypto.aes(
                .cbc,
                encrypt: route.hasSuffix("encrypt_bytes"),
                input: try bytes(args, 0, "input"),
                key: try bytes(args, 1, "key"),
                iv: try bytes(args, 2, "iv"),
                aad: nil
            )
            return try encode(PluginCrypto.digestPayload(result))

        case "crypto.aes_gcm_encrypt_bytes", "crypto.aes_gcm_decrypt_bytes":
            let result = try PluginCrypto.aes(
                .gcm,
                encrypt: route.hasSuffix("encrypt_bytes"),
                input: try bytes(args, 0, "input"),
                key: try bytes(args, 1, "key"),
                iv: try bytes(args, 2, "nonce"),
                aad: try optionalBytes(args, 3)
            )
            return try encode(PluginCrypto.digestPayload(result))

        case "crypto.timing_safe_equal_bytes":
            let equal = PluginCrypto.timingSafeEqual(try bytes(args, 0, "left"), try bytes(args, 1, "right"))
            return try encode(["equal": equal])

        case "crypto.random_bytes":
            return try encode(try PluginCrypto.randomBytes(try integer(args, 0, "size")).map(Int.init))

        case "crypto.random_uuid_v4":
            return try encode(["uuid": PluginCrypto.randomUUID()])

        default:
            throw PluginError.unsupportedRoute(route)
        }
    }

    // MARK: - 路由后缀解析

    /// 从路由名里取出摘要算法，例如 `crypto.hmac_sha256_bytes` → `sha256`
    private static func algorithm(_ route: String) throws -> PluginCrypto.Digest {
        for candidate in ["sha512", "sha256", "sha1", "md5"] where route.contains(candidate) {
            guard let digest = PluginCrypto.Digest(rawValue: candidate) else { break }
            return digest
        }
        throw PluginError.unsupportedRoute(route)
    }

    // MARK: - 参数解码

    private static func bytes(_ args: [Any], _ index: Int, _ name: String) throws -> Data {
        guard args.indices.contains(index) else {
            throw PluginError.invalidPayload("缺少参数 \(name)")
        }
        guard let items = args[index] as? [Any] else {
            throw PluginError.invalidPayload("参数 \(name) 必须是字节数组")
        }

        var data = Data()
        data.reserveCapacity(items.count)
        for item in items {
            guard let byte = byteValue(item) else {
                throw PluginError.invalidPayload("参数 \(name) 的每个字节必须在 0-255 之间")
            }
            data.append(byte)
        }
        return data
    }

    /// 字节可能来自 JSON 数字（NSNumber）、Int，或 Swift 侧直接传的 UInt8
    private static func byteValue(_ value: Any) -> UInt8? {
        if let number = value as? NSNumber {
            let int = number.intValue
            return (0...255).contains(int) ? UInt8(int) : nil
        }
        if let number = value as? Double {
            return number == number.rounded() && (0...255).contains(number) ? UInt8(number) : nil
        }
        return nil
    }

    private static func optionalBytes(_ args: [Any], _ index: Int) throws -> Data? {
        guard args.indices.contains(index), !(args[index] is NSNull) else { return nil }
        return try bytes(args, index, "参数 \(index + 1)")
    }

    private static func text(_ args: [Any], _ index: Int, _ name: String) throws -> String {
        guard args.indices.contains(index), let value = args[index] as? String else {
            throw PluginError.invalidPayload("参数 \(name) 必须是字符串")
        }
        return value
    }

    private static func base64(_ args: [Any], _ index: Int, _ name: String) throws -> Data {
        guard let data = Data(base64Encoded: try text(args, index, name)) else {
            throw PluginError.invalidPayload("参数 \(name) 不是合法 Base64")
        }
        return data
    }

    private static func integer(_ args: [Any], _ index: Int, _ name: String) throws -> Int {
        guard args.indices.contains(index), let value = args[index] as? NSNumber else {
            throw PluginError.invalidPayload("参数 \(name) 必须是整数")
        }
        return value.intValue
    }

    // MARK: - 编码

    private static func encode(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }

    /// 字节结果按整数数组返回，与 Breeze 的 JSON 出口一致
    private static func encode(bytes: Data) throws -> String {
        try encode(bytes.map(Int.init))
    }
}
