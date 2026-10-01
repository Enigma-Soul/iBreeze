import Foundation
import os

/// 云端插件条目（Breeze-plugin-list 的 `plugins_data.json`）
struct RemotePlugin: Codable, Hashable, Sendable, Identifiable {
    var repo: String
    var manifest: PluginManifest

    var id: String { manifest.uuid }
}

/// 插件的下载坐标：npm 优先，GitHub Release 兜底
struct PluginDownloadChannel: Hashable, Sendable {
    var npmName: String?
    var version: String?
    var updateURL: String?

    init(npmName: String?, version: String? = nil, updateURL: String?) {
        self.npmName = npmName?.isEmpty == false ? npmName : nil
        self.version = version?.isEmpty == false ? version : nil
        self.updateURL = updateURL?.isEmpty == false ? updateURL : nil
    }

    var isEmpty: Bool { npmName == nil && updateURL == nil }
}

/// 插件安装与更新。
///
/// 与 Breeze 一致：安装时不看清单文件，而是把 bundle 塞进一次性运行时跑
/// `getInfo()`，用它返回的 uuid / version 作为权威信息。
final class PluginInstaller: @unchecked Sendable {
    /// jsDelivr 及其国内可达转发，按实测可达性排序（前两个在国内更稳）
    private static let cdnMirrors = [
        "https://cdn.jsdmirror.com/",
        "https://cdn.jsdmirror.cn/",
        "https://cdn.jsdelivr.net/",
        "https://jsd.onmicrosoft.cn/",
        "https://www.webcache.cn/"
    ]

    /// GitHub 加速前缀：Release 资产与 API 在国内经常直连不上
    private static let gitHubProxies = [
        "https://ghfast.top/",
        "https://gh-proxy.com/"
    ]

    private let downloader: PluginDownloading
    private let store: PluginStore
    private let logger = Logger(subsystem: "com.enigma-soul.ibreeze", category: "PluginInstaller")

    init(downloader: PluginDownloading = URLSessionDownloader(), store: PluginStore = .shared) {
        self.downloader = downloader
        self.store = store
    }

    /// 从云端条目安装
    @discardableResult
    func install(_ remote: RemotePlugin) async throws -> InstalledPlugin {
        let bundle = try await downloadBundle(channel: PluginDownloadChannel(
            npmName: remote.manifest.npmName,
            version: remote.manifest.version,
            updateURL: remote.manifest.updateUrl
        ))
        return try await install(bundle: bundle, expectedUUID: nil)
    }

    /// 从用户给定的 bundle 地址安装
    @discardableResult
    func install(bundleURL: URL) async throws -> InstalledPlugin {
        let data = try await downloader.data(from: bundleURL)
        guard let bundle = String(data: data, encoding: .utf8) else {
            throw PluginInstallError.invalidBundle("不是 UTF-8 文本")
        }
        return try await install(bundle: bundle, expectedUUID: nil)
    }

    /// 检查并安装更新，返回是否真的更新了
    @discardableResult
    func update(_ plugin: InstalledPlugin, force: Bool = false) async throws -> Bool {
        let bundle = try await downloadBundle(channel: PluginDownloadChannel(
            npmName: plugin.npmName,
            version: nil,
            updateURL: plugin.updateURL
        ))

        // 先用一次性运行时读出远端版本，再决定是否落盘
        let probe = try await probe(bundle: bundle)
        guard force || PluginVersion.isNewer(probe.version ?? "0", than: plugin.version) else {
            logger.info("插件 \(plugin.name, privacy: .public) 已是最新版本")
            return false
        }
        _ = try await persist(bundle: bundle, expectedUUID: plugin.uuid)
        return true
    }

    /// 安装已下载好的 bundle
    @discardableResult
    func install(bundle: String, expectedUUID: String?) async throws -> InstalledPlugin {
        try await persist(bundle: bundle, expectedUUID: expectedUUID)
    }

    // MARK: - 内部实现

    private func persist(bundle: String, expectedUUID: String?) async throws -> InstalledPlugin {
        let manifest = try await probe(bundle: bundle)
        if let expectedUUID, manifest.uuid != expectedUUID {
            throw PluginInstallError.uuidMismatch(expected: expectedUUID, actual: manifest.uuid)
        }

        let plugin = InstalledPlugin(manifest: manifest)
        try store.save(plugin, bundle: bundle)
        return plugin
    }

    /// 用一次性运行时跑 `getInfo()`，不常驻
    private func probe(bundle: String) async throws -> PluginManifest {
        let pluginID = UUID().uuidString
        let runtime = PluginRuntime(pluginID: pluginID, host: PluginHostBridge(pluginID: pluginID))
        defer { Task { await runtime.shutdown() } }

        try await runtime.load(bundle: bundle)
        return try await runtime.invoke(PluginManifest.self, fnPath: "getInfo")
    }

    /// 下载 bundle：npm（jsDelivr 多镜像）优先，失败再退回 GitHub Release
    private func downloadBundle(channel: PluginDownloadChannel) async throws -> String {
        guard !channel.isEmpty else { throw PluginInstallError.missingDownloadChannel }

        if let npmName = channel.npmName, let bundle = try? await downloadFromNPM(npmName: npmName, version: channel.version) {
            return bundle
        }
        if let updateURL = channel.updateURL, let url = URL(string: updateURL) {
            if let bundle = try? await downloadFromRelease(apiURL: url) {
                return bundle
            }
        }
        throw PluginInstallError.missingDownloadChannel
    }

    private func downloadFromNPM(npmName: String, version: String?) async throws -> String {
        let tag = version ?? "latest"
        var lastError: Error = PluginInstallError.missingDownloadChannel

        for mirror in Self.cdnMirrors {
            let address = "\(mirror)npm/\(npmName)@\(tag)/dist/\(npmName).bundle.cjs"
            guard let url = URL(string: address) else { continue }
            do {
                return try await text(from: url, emptyReason: "npm 返回内容为空")
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func downloadFromRelease(apiURL: URL) async throws -> String {
        let release = try await fetchRelease(apiURL: apiURL)

        // 暂不支持 brotli，因此只挑未压缩的 .cjs
        let asset = release.assets?.first { asset in
            asset.name.hasSuffix(".bundle.cjs") || asset.name.hasSuffix(".cjs")
        }
        guard let asset else { throw PluginInstallError.noCompatibleAsset }

        var lastError: Error = PluginInstallError.noCompatibleAsset
        for address in assetCandidates(asset: asset, release: release, apiURL: apiURL) {
            guard let url = URL(string: address) else { continue }
            do {
                return try await text(from: url, emptyReason: "Release 资产内容为空")
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Release 信息：直连 API 优先，失败再走加速前缀
    private func fetchRelease(apiURL: URL) async throws -> Release {
        var lastError: Error?

        for address in [apiURL.absoluteString] + Self.gitHubProxies.map({ "\($0)\(apiURL.absoluteString)" }) {
            guard let url = URL(string: address) else { continue }
            do {
                let data = try await downloader.data(from: url)
                return try JSONDecoder().decode(Release.self, from: data)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? PluginInstallError.missingDownloadChannel
    }

    /// 资产候选地址：直连 → 加速前缀 → jsDelivr 的 gh 通道（部分插件把 dist 提交进仓库）
    private func assetCandidates(asset: Release.Asset, release: Release, apiURL: URL) -> [String] {
        var candidates = [asset.browserDownloadURL]
        candidates += Self.gitHubProxies.map { "\($0)\(asset.browserDownloadURL)" }

        if let tag = release.tagName, let repoPath = Self.repositoryPath(from: apiURL) {
            candidates += Self.cdnMirrors.map { "\($0)gh/\(repoPath)@\(tag)/\(asset.name)" }
        }
        return candidates
    }

    private func text(from url: URL, emptyReason: String) async throws -> String {
        let data = try await downloader.data(from: url)
        guard let bundle = String(data: data, encoding: .utf8), !bundle.isEmpty else {
            throw PluginInstallError.invalidBundle(emptyReason)
        }
        return bundle
    }

    /// 从 `https://api.github.com/repos/{owner}/{repo}/releases/latest` 里取出 `owner/repo`
    private static func repositoryPath(from apiURL: URL) -> String? {
        let parts = apiURL.pathComponents
        guard let index = parts.firstIndex(of: "repos"), parts.count > index + 2 else { return nil }
        return "\(parts[index + 1])/\(parts[index + 2])"
    }

    /// GitHub Release API 的最小字段集
    private struct Release: Decodable {
        var tagName: String?
        var assets: [Asset]?

        struct Asset: Decodable {
            var name: String
            var browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }
}
