import Foundation

/// 云端插件列表：直接读 Breeze 的插件清单仓库，与官方客户端同一份数据
final class PluginRepository: @unchecked Sendable {
    private static let listURL = URL(
        string: "https://raw.githubusercontent.com/deretame/Breeze-plugin-list/main/plugins_data.json"
    )!

    private let downloader: PluginDownloading

    init(downloader: PluginDownloading = URLSessionDownloader()) {
        self.downloader = downloader
    }

    func fetch() async throws -> [RemotePlugin] {
        let data = try await downloader.data(from: Self.listURL)
        return try JSONDecoder().decode([RemotePlugin].self, from: data)
    }
}
