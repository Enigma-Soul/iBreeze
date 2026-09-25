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

    /// 同时下载的上限：图源不通时并发太多会把整页拖住
    private static let maxConcurrent = 4

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
        memory.countLimit = 200
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
            memory.setObject(image, forKey: key as NSString)
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

        do {
            let data = try await source.imageBytes(url: url, extern: extern)
            guard let image = UIImage(data: data) else {
                logger.error("图片解码失败：\(url, privacy: .public)")
                return .failure("图片解码失败")
            }
            try? data.write(to: fileURL(for: key), options: .atomic)
            return .success(image)
        } catch {
            logger.error("图片下载失败：\(error.localizedDescription, privacy: .public)")
            return .failure(error.localizedDescription)
        }
    }

    private func loadFromDisk(key: String) async -> UIImage? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key)
    }

    /// 下载并发闸门：拿不到槽位就排队，槽位直接转交给下一个等待者
    private func acquireSlot() async {
        if activeDownloads < Self.maxConcurrent {
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
