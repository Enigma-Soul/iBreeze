import Foundation

/// 代理连通性测试。
///
/// 用一个国内直连不通、走代理才通的地址来判定：能通就说明代理确实生效了。
enum ProxyTester {
    struct Outcome {
        let success: Bool
        let message: String
    }

    private static let probeURL = URL(string: "https://www.google.com/generate_204")!

    static func test(proxy: ProxyConfiguration?) async -> Outcome {
        guard let proxy else {
            return Outcome(success: false, message: "代理未启用，请先打开开关并填好服务器与端口")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = proxy.connectionProxyDictionary
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration)

        do {
            let (_, response) = try await session.data(from: probeURL)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            return (200..<400).contains(status)
                ? Outcome(success: true, message: "代理已生效（\(proxy.type.title) \(proxy.host):\(proxy.port)）")
                : Outcome(success: false, message: "代理返回 HTTP \(status)，请检查服务器配置")
        } catch {
            return Outcome(success: false, message: "代理测试失败：\(error.localizedDescription)")
        }
    }
}
