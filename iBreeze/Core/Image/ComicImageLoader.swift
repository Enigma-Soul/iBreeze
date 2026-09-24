import UIKit
import os

/// 漫画图片加载：内存 + 磁盘两级缓存，未命中时交给插件去取字节。
///
/// 插件返回的 `ImageItem.url` 只是个占位符，真正下载由插件的
/// `fetchImageBytes` 完成，所以缓存键必须带上插件 uuid。
actor ComicImageLoader {
    static let shared = ComicImageLoader()

    private let logger = Logger(subsystem: "com.enigma-soul.ibreeze", category: "ComicImage")
    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    /// 同一张图只允许一个在途请求
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ComicImages", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        memory.countLimit = 200
    }

    /// 取图：命中缓存直接返回，否则让插件下载
    func image(pluginUUID: String, url: String, source: PluginSource) async -> UIImage? {
        let key = Self.cacheKey(pluginUUID: pluginUUID, url: url)

        if let cached = memory.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return await task.value }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            if let image = await loadFromDisk(key: key) { return image }
            return await download(key: key, url: url, source: source)
        }
        inFlight[key] = task

        let image = await task.value
        inFlight[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }

    /// 预取，用于阅读页提前加载后几页
    func prefetch(pluginUUID: String, urls: [String], source: PluginSource) {
        for url in urls {
            Task { _ = await image(pluginUUID: pluginUUID, url: url, source: source) }
        }
    }

    private func download(key: String, url: String, source: PluginSource) async -> UIImage? {
        do {
            let data = try await source.imageBytes(url: url)
            guard let image = UIImage(data: data) else {
                logger.error("图片解码失败：\(url, privacy: .public)")
                return nil
            }
            try? data.write(to: fileURL(for: key), options: .atomic)
            return image
        } catch {
            logger.error("图片下载失败：\(error.localizedDescription, privacy: .public)")
            return nil
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

    /// 缓存键：插件 uuid + 图片地址的摘要，避免文件名过长或非法
    private static func cacheKey(pluginUUID: String, url: String) -> String {
        let digest = PluginCrypto.digest(.sha256, Data("\(pluginUUID)|\(url)".utf8))
        return PluginCrypto.hex(digest)
    }
}
