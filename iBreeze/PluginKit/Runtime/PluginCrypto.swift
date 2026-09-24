import CommonCrypto
import CryptoKit
import Foundation
import Security

/// 插件可用的加密能力，语义对齐 Breeze 的 `crypto.*` 路由与 `__crypto_*` 钩子
enum PluginCrypto {
    /// 支持的摘要算法
    enum Digest: String {
        case md5
        case sha1
        case sha256
        case sha512
    }

    /// AES 分组模式
    enum AESMode {
        case ecb
        case cbc
        case gcm
    }

    enum CryptoError: LocalizedError {
        case unknownDigest(String)
        case invalidKeyLength
        case operationFailed(String)
        case decryptionFailed

        var errorDescription: String? {
            switch self {
            case .unknownDigest(let name): "不支持的摘要算法：\(name)"
            case .invalidKeyLength: "AES 密钥长度必须是 16 / 24 / 32 字节"
            case .operationFailed(let detail): "加密运算失败：\(detail)"
            case .decryptionFailed: "解密失败：密钥、向量或密文不正确"
            }
        }
    }

    // MARK: - 摘要与 HMAC

    static func digest(_ algorithm: Digest, _ input: Data) -> Data {
        switch algorithm {
        case .md5: Data(Insecure.MD5.hash(data: input))
        case .sha1: Data(Insecure.SHA1.hash(data: input))
        case .sha256: Data(SHA256.hash(data: input))
        case .sha512: Data(SHA512.hash(data: input))
        }
    }

    static func hmac(_ algorithm: Digest, key: Data, data: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        switch algorithm {
        case .md5:
            // Breeze 的 hmac 只支持 sha1 / sha256 / sha512
            throw CryptoError.unknownDigest("hmac-md5")
        case .sha1:
            return Data(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symmetricKey))
        case .sha256:
            return Data(HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey))
        case .sha512:
            return Data(HMAC<SHA512>.authenticationCode(for: data, using: symmetricKey))
        }
    }

    // MARK: - AES

    static func aes(_ mode: AESMode, encrypt: Bool, input: Data, key: Data, iv: Data?, aad: Data?) throws -> Data {
        guard [16, 24, 32].contains(key.count) else { throw CryptoError.invalidKeyLength }

        switch mode {
        case .ecb, .cbc:
            let options = CCOptions(kCCOptionPKCS7Padding) | (mode == .ecb ? CCOptions(kCCOptionECBMode) : 0)
            return try crypt(
                encrypt ? CCOperation(kCCEncrypt) : CCOperation(kCCDecrypt),
                options: options,
                input: input,
                key: key,
                iv: iv ?? Data(count: kCCBlockSizeAES128)
            )

        case .gcm:
            guard let nonce = iv, let box = try? AES.GCM.Nonce(data: nonce) else {
                throw CryptoError.operationFailed("GCM 需要 12 字节 nonce")
            }
            let symmetricKey = SymmetricKey(data: key)
            if encrypt {
                // 与 Breeze 一致：输出为 密文 + 16 字节 tag
                let sealed = try sealGCM(input, key: symmetricKey, nonce: box, aad: aad)
                return sealed.ciphertext + sealed.tag
            }
            guard input.count > 16 else { throw CryptoError.decryptionFailed }
            let sealedBox = try AES.GCM.SealedBox(
                nonce: box,
                ciphertext: input.prefix(input.count - 16),
                tag: input.suffix(16)
            )
            return try openGCM(sealedBox, key: symmetricKey, aad: aad)
        }
    }

    // MARK: - PBKDF2 与随机数

    static func pbkdf2SHA256(password: Data, salt: Data, rounds: Int, keyLength: Int) throws -> Data {
        guard rounds > 0, keyLength > 0 else {
            throw CryptoError.operationFailed("迭代次数与派生长度必须是正整数")
        }

        var derived = Data(count: keyLength)
        let passwordCount = password.count
        let saltCount = salt.count
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self), passwordCount,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), saltCount,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(rounds),
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.operationFailed("PBKDF2 返回 \(status)") }
        return derived
    }

    static func randomBytes(_ count: Int) throws -> Data {
        guard count > 0 else { return Data() }

        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        guard status == errSecSuccess else { throw CryptoError.operationFailed("随机数生成失败") }
        return bytes
    }

    static func randomUUID() -> String { UUID().uuidString.lowercased() }

    static func timingSafeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }

    // MARK: - 编码辅助

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// 加密结果统一按 `{ hex, base64 }` 返回，与 Breeze 的钩子出参一致
    static func digestPayload(_ data: Data) -> [String: String] {
        ["hex": hex(data), "base64": data.base64EncodedString()]
    }

    // MARK: - CommonCrypto 兜底

    private static func sealGCM(
        _ input: Data,
        key: SymmetricKey,
        nonce: AES.GCM.Nonce,
        aad: Data?
    ) throws -> AES.GCM.SealedBox {
        do {
            if let aad {
                return try AES.GCM.seal(input, using: key, nonce: nonce, authenticating: aad)
            }
            return try AES.GCM.seal(input, using: key, nonce: nonce)
        } catch {
            throw CryptoError.operationFailed("GCM 加密失败")
        }
    }

    private static func openGCM(_ box: AES.GCM.SealedBox, key: SymmetricKey, aad: Data?) throws -> Data {
        do {
            if let aad {
                return try AES.GCM.open(box, using: key, authenticating: aad)
            }
            return try AES.GCM.open(box, using: key)
        } catch {
            throw CryptoError.decryptionFailed
        }
    }

    private static func crypt(
        _ operation: CCOperation,
        options: CCOptions,
        input: Data,
        key: Data,
        iv: Data
    ) throws -> Data {
        guard !input.isEmpty else { return Data() }

        var output = Data(count: input.count + kCCBlockSizeAES128)
        var produced = 0
        // 借用之前先把长度取出来，避免闭包内重叠访问
        let keyCount = key.count
        let inputCount = input.count
        let capacity = output.count
        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation, CCAlgorithm(kCCAlgorithmAES), options,
                            keyBytes.baseAddress, keyCount,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress, inputCount,
                            outputBytes.baseAddress, capacity,
                            &produced
                        )
                    }
                }
            }
        }

        switch Int(status) {
        case kCCSuccess: return output.prefix(produced)
        case kCCDecodeError, kCCAlignmentError: throw CryptoError.decryptionFailed
        default: throw CryptoError.operationFailed("CCCrypt 返回 \(status)")
        }
    }
}
