import Foundation

/// 安装器用到的下载能力，抽出来便于测试替换
protocol PluginDownloading: Sendable {
    func data(from url: URL) async throws -> Data
}

/// 默认实现：URLSession，带 20 秒超时
struct URLSessionDownloader: PluginDownloading {
    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("iBreeze", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PluginInstallError.downloadFailed(url.absoluteString, http.statusCode)
        }
        return data
    }
}

/// 安装过程中的错误
enum PluginInstallError: LocalizedError, Equatable {
    case missingDownloadChannel
    case downloadFailed(String, Int?)
    case invalidBundle(String)
    case uuidMismatch(expected: String, actual: String)
    case noCompatibleAsset

    var errorDescription: String? {
        switch self {
        case .missingDownloadChannel: "该插件既没有 npmName 也没有 updateUrl，无法下载"
        case .downloadFailed(let url, let status):
            status.map { "下载失败（HTTP \($0)）：\(url)" } ?? "下载失败：\(url)"
        case .invalidBundle(let detail): "插件包无法使用：\(detail)"
        case .uuidMismatch(let expected, let actual):
            "插件 UUID 不一致（期望 \(expected)，实际 \(actual)），已拒绝安装"
        case .noCompatibleAsset: "Release 里没有可用的 .cjs 资产"
        }
    }
}
