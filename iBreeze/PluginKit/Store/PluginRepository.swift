import Foundation

/// 云端插件列表：读 Breeze 的插件清单仓库，与官方客户端同一份数据。
///
/// 国内直连 raw.githubusercontent 基本不通，因此先走 jsDelivr 的 gh 通道
/// （与 Breeze 同一组镜像），全部失败才回退直连。
final class PluginRepository: @unchecked Sendable {
    private static let listPath = "gh/deretame/Breeze-plugin-list@main/plugins_data.json"
    private static let directURL = URL(
        string: "https://raw.githubusercontent.com/deretame/Breeze-plugin-list/main/plugins_data.json"
    )!

    private static let mirrors = [
        "https://cdn.jsdmirror.com/",
        "https://cdn.jsdmirror.cn/",
        "https://cdn.jsdelivr.net/",
        "https://jsd.onmicrosoft.cn/"
    ]

    private let downloader: PluginDownloading

    init(downloader: PluginDownloading = URLSessionDownloader()) {
        self.downloader = downloader
    }

    func fetch() async throws -> [RemotePlugin] {
        var lastError: Error = PluginInstallError.downloadFailed(Self.directURL.absoluteString, nil)

        for address in Self.mirrors.map({ "\($0)\(Self.listPath)" }) + [Self.directURL.absoluteString] {
            guard let url = URL(string: address) else { continue }
            do {
                let data = try await downloader.data(from: url)
                return try JSONDecoder().decode([RemotePlugin].self, from: data)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
