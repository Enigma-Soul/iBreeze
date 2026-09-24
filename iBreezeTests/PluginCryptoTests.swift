import Foundation
import Testing
@testable import iBreeze

/// 向量取自 Node 的 `crypto` 模块，与 Breeze 的 Rust 实现同源算法
@Suite("插件加密")
struct PluginCryptoTests {
    private static let hello = Data("hello".utf8)
    private static let key = Data(repeating: 0x2b, count: 32)

    @Test("摘要算法结果正确")
    func digests() {
        #expect(PluginCrypto.hex(PluginCrypto.digest(.md5, Self.hello)) == "5d41402abc4b2a76b9719d911017c592")
        #expect(PluginCrypto.hex(PluginCrypto.digest(.sha1, Self.hello)) == "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
        #expect(PluginCrypto.hex(PluginCrypto.digest(.sha256, Self.hello))
            == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(PluginCrypto.hex(PluginCrypto.digest(.sha512, Self.hello))
            == "9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca72323c3d99ba5c11d7c7acc6e14b8c5da0c4663475c2e5c3adef46f73bcdec043")
    }

    @Test("HMAC-SHA256 结果正确")
    func hmac() throws {
        let mac = try PluginCrypto.hmac(.sha256, key: Data("key".utf8), data: Self.hello)
        #expect(PluginCrypto.hex(mac) == "9307b3b915efb5171ff14d8cb55fbcc798c6c0ef1456d66ded1a6aa723a58b7b")
    }

    @Test("PBKDF2-SHA256 结果正确")
    func pbkdf2() throws {
        let derived = try PluginCrypto.pbkdf2SHA256(
            password: Data("password".utf8),
            salt: Data("salt".utf8),
            rounds: 1,
            keyLength: 32
        )
        #expect(PluginCrypto.hex(derived) == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    }

    @Test("AES-CBC 与 GCM 都能还原明文")
    func aesRoundTrip() throws {
        let plaintext = Data("iBreeze 加密测试".utf8)

        let iv = Data(repeating: 0x1a, count: 16)
        let ciphertext = try PluginCrypto.aes(.cbc, encrypt: true, input: plaintext, key: Self.key, iv: iv, aad: nil)
        #expect(ciphertext != plaintext)
        #expect(try PluginCrypto.aes(.cbc, encrypt: false, input: ciphertext, key: Self.key, iv: iv, aad: nil) == plaintext)

        let nonce = Data(repeating: 0x07, count: 12)
        let sealed = try PluginCrypto.aes(.gcm, encrypt: true, input: plaintext, key: Self.key, iv: nonce, aad: Data("aad".utf8))
        #expect(try PluginCrypto.aes(.gcm, encrypt: false, input: sealed, key: Self.key, iv: nonce, aad: Data("aad".utf8)) == plaintext)
    }

    @Test("密钥长度不合法时报错")
    func invalidKeyLength() {
        #expect(throws: PluginCrypto.CryptoError.self) {
            try PluginCrypto.aes(.cbc, encrypt: true, input: Data("x".utf8), key: Data([1, 2, 3]), iv: Data(count: 16), aad: nil)
        }
    }

    @Test("随机数与定长比较")
    func randomAndCompare() throws {
        #expect(try PluginCrypto.randomBytes(16).count == 16)
        #expect(PluginCrypto.timingSafeEqual(Data([1, 2, 3]), Data([1, 2, 3])))
        #expect(!PluginCrypto.timingSafeEqual(Data([1, 2, 3]), Data([1, 2, 4])))
        #expect(!PluginCrypto.timingSafeEqual(Data([1, 2, 3]), Data([1, 2])))
    }
}

@Suite("加密路由")
struct PluginCryptoRouteTests {
    private func makeBridge() -> PluginHostBridge {
        PluginHostBridge(pluginID: UUID().uuidString)
    }

    @Test("异步路由：_hex 系列接受字符串")
    func asyncHexRoutes() async throws {
        let bridge = makeBridge()

        #expect(try await bridge.dispatch(route: "crypto.md5_hex", argsJSON: #"["hello"]"#)
            == #""5d41402abc4b2a76b9719d911017c592""#)
        #expect(try await bridge.dispatch(route: "crypto.sha256_hex", argsJSON: #"["hello"]"#)
            == #""2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824""#)
        #expect(try await bridge.dispatch(route: "crypto.hmac_sha256_hex", argsJSON: #"["key","hello"]"#)
            == #""9307b3b915efb5171ff14d8cb55fbcc798c6c0ef1456d66ded1a6aa723a58b7b""#)
    }

    @Test("异步路由：字节数组进、十六进制出")
    func asyncByteRoutes() async throws {
        let bridge = makeBridge()
        let result = try await bridge.dispatch(route: "crypto.sha256", argsJSON: "[[104,101,108,108,111]]")

        #expect(result == #""2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824""#)
    }

    /// 把路由返回的 JSON 文本解成字典
    private func decode<T>(_ payload: String?) throws -> T? {
        guard let payload, let data = payload.data(using: .utf8) else { return nil }
        return try JSONSerialization.jsonObject(with: data) as? T
    }

    @Test("同步钩子：返回 hex 与 base64")
    func syncHooks() throws {
        let payload = try PluginCryptoRoutes.dispatchSync(route: "crypto.sha256_bytes", args: [[104, 101, 108, 108, 111]])
        let object: [String: String]? = try decode(payload)

        #expect(object?["hex"] == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(object?["base64"] == "LPJNul+wow4m6DsqxbninhsWHlwfp0JecwQzYpOLmCQ=")
    }

    @Test("同步钩子：pbkdf2 与随机数")
    func syncPbkdf2AndRandom() throws {
        let derived = try PluginCryptoRoutes.dispatchSync(
            route: "crypto.pbkdf2_sha256_bytes",
            args: [Array("password".utf8), Array("salt".utf8), 1, 32]
        )
        let derivedObject: [String: String]? = try decode(derived)
        #expect(derivedObject?["hex"] == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")

        let random = try PluginCryptoRoutes.dispatchSync(route: "crypto.random_bytes", args: [8])
        let randomBytes: [Int]? = try decode(random)
        #expect(randomBytes?.count == 8)
    }

    @Test("同步钩子：定长比较返回 equal")
    func syncTimingSafeEqual() throws {
        let payload = try PluginCryptoRoutes.dispatchSync(route: "crypto.timing_safe_equal_bytes", args: [[1, 2, 3], [1, 2, 3]])
        let object: [String: Bool]? = try decode(payload)

        #expect(object?["equal"] == true)
    }

    @Test("非加密路由返回 nil，交给上层兜底")
    func notCryptoRoute() throws {
        #expect(try PluginCryptoRoutes.dispatch(route: "cache.get", args: []) == nil)
        #expect(try PluginCryptoRoutes.dispatchSync(route: "cache.get.sync", args: []) == nil)
    }
}
