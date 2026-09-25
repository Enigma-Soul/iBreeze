import UIKit
import os

/// 漫画图片加载：内存 + 磁盘两级缓存，未命中时交给插件去取字节。
///
/// 插件返回的 `ImageItem.url` 只是个占位符，真正下载由插件的
/// `fetchImageBytes` 完成，所以缓存键必须带上插件 uuid。
actor ComicImageLoader {
    static let shared = ComicImageLoader()

    enum Outcome {
        case success(UIImage)
        case failure(String)
    }

    /// 内存缓存按字节计费，长条漫画也不至于把内存吃满
    private static let memoryCostLimit = 200 * 1024 * 1024

    private let logger = Logger(subsystem: "com.enigma-soul.ibreeze", category: "ComicImage")
    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    /// 同一张图只允许一个在途请求
    private var inFlight: [String: Task<Outcome, Never>] = [:]

    private var activeDownloads = 0
    private var waitingSlots: [CheckedContinuation<Void, Never>] = []

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ComicImages", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        memory.countLimit = 400
        memory.totalCostLimit = Self.memoryCostLimit
    }

    /// 取图：命中缓存直接返回，否则让插件下载。
    ///
    /// `extern` 是页面上带的透传上下文，可能包含真实图址，必须原样回传给插件，
    /// 因此也要参与缓存键。
    func load(pluginUUID: String, url: String, extern: JSONValue? = nil, source: PluginSource) async -> Outcome {
        let key = Self.cacheKey(pluginUUID: pluginUUID, url: url, extern: extern)

        if let cached = memory.object(forKey: key as NSString) { return .success(cached) }
        if let task = inFlight[key] { return await task.value }

        let task = Task<Outcome, Never> { [weak self] in
            guard let self else { return .failure("加载器已释放") }
            if let image = await loadFromDisk(key: key) { return .success(image) }
            return await download(key: key, url: url, extern: extern, source: source)
        }
        inFlight[key] = task

        let outcome = await task.value
        inFlight[key] = nil
        if case .success(let image) = outcome {
            memory.setObject(image, forKey: key as NSString, cost: image.memoryCost)
        }
        return outcome
    }

    /// 只要图片本身，失败返回 nil
    func image(pluginUUID: String, url: String, source: PluginSource) async -> UIImage? {
        if case .success(let image) = await load(pluginUUID: pluginUUID, url: url, source: source) {
            return image
        }
        return nil
    }

    /// 预取，用于阅读页提前加载后几页
    func prefetch(pluginUUID: String, pages: [(url: String, extern: JSONValue?)], source: PluginSource) {
        for page in pages {
            Task { _ = await load(pluginUUID: pluginUUID, url: page.url, extern: page.extern, source: source) }
        }
    }

    /// 清空内存与磁盘缓存
    func clear() {
        memory.removeAllObjects()
        inFlight.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logger.info("已清空图片缓存")
    }

    // MARK: - 内部实现

    private func download(key: String, url: String, extern: JSONValue?, source: PluginSource) async -> Outcome {
        await acquireSlot()
        defer { releaseSlot() }

        let timeout = ImageSettings.timeoutSeconds
        var lastError = "图片下载失败"

        // 超时或网络抖动时重试一次，图源慢的时候很有用
        for attempt in 0..<2 {
            do {
                let data = try await withTimeout(seconds: timeout) {
                    try await source.imageBytes(url: url, extern: extern, timeoutMs: timeout * 1000)
                }
                guard let image = UIImage(data: data) else {
                    logger.error("图片解码失败：\(url, privacy: .public)")
                    return .failure("图片解码失败")
                }
                try? data.write(to: fileURL(for: key), options: .atomic)
                return .success(image)
            } catch {
                lastError = error.localizedDescription
                logger.error("图片下载失败（第 \(attempt + 1) 次）：\(lastError, privacy: .public)")
            }
        }

        return .failure(lastError)
    }

    /// 宿主侧兜底超时：插件自己也有 timeoutMs，但卡在 JS 里时得由这里掐断
    private func withTimeout<T: Sendable>(
        seconds: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                throw PluginError.pluginThrew("图片下载超时（\(seconds) 秒）")
            }

            defer { group.cancelAll() }
            guard let value = try await group.next() else {
                throw PluginError.pluginThrew("图片下载失败")
            }
            return value
        }
    }

    private func loadFromDisk(key: String) async -> UIImage? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString, cost: image.memoryCost)
        return image
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key)
    }

    /// 下载并发闸门：拿不到槽位就排队，槽位直接转交给下一个等待者
    private func acquireSlot() async {
        if activeDownloads < ImageSettings.concurrency {
            activeDownloads += 1
            return
        }
        await withCheckedContinuation { waitingSlots.append($0) }
    }

    private func releaseSlot() {
        guard !waitingSlots.isEmpty else {
            activeDownloads = max(0, activeDownloads - 1)
            return
        }
        waitingSlots.removeFirst().resume()
    }

    /// 缓存键：插件 uuid + 图片地址 + 透传上下文的摘要，避免文件名过长或非法
    private static func cacheKey(pluginUUID: String, url: String, extern: JSONValue?) -> String {
        var material = "\(pluginUUID)|\(url)"
        if let extern, let data = try? sortedEncoder.encode(extern) {
            material += "|" + String(decoding: data, as: UTF8.self)
        }
        return PluginCrypto.hex(PluginCrypto.digest(.sha256, Data(material.utf8)))
    }

    private static let sortedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private extension UIImage {
    /// 粗略估算解码后的内存占用，用于内存缓存计费
    var memoryCost: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
