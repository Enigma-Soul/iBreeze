import Foundation

/// 插件网络请求：URLSession + 代理配置
final class PluginHTTPClient: @unchecked Sendable {
    /// JS 侧用来声明「本次响应要按二进制返回」的头，不需要转发给上游
    private static let binaryOffloadHeader = "x-rquickjs-host-offload-binary-v1"

    private let lock = NSLock()
    private var tasks: [Int: URLSessionDataTask] = [:]
    private var session: URLSession
    /// 建 session 时用的代理配置，设置页改动后自动重建
    private var proxy: ProxyConfiguration?

    init(proxy: ProxyConfiguration? = ProxyConfiguration.current()) {
        self.proxy = proxy
        session = Self.makeSession(proxy: proxy)
    }

    /// 执行请求，返回给 JS 的负载，响应体以 base64 回传
    func request(
        id: Int,
        method: String,
        urlString: String,
        headers: [String: String],
        bodyText: String?,
        bodyBase64: String?
    ) async -> [String: Any] {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return ["ok": false, "error": "非法的请求地址：\(urlString)"]
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        for (name, value) in headers where name.lowercased() != Self.binaryOffloadHeader {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let bodyBase64, let data = Data(base64Encoded: bodyBase64) {
            request.httpBody = data
        } else if let bodyText {
            request.httpBody = Data(bodyText.utf8)
        }

        do {
            let (data, response) = try await perform(request, id: id, session: currentSession())
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            return [
                "ok": true,
                "status": status,
                "statusText": HTTPURLResponse.localizedString(forStatusCode: status),
                "headers": Self.flatten(http),
                "url": response.url?.absoluteString ?? url.absoluteString,
                "bodyBase64": data.base64EncodedString()
            ]
        } catch {
            if (error as NSError).code == NSURLErrorCancelled {
                return ["ok": false, "canceled": true]
            }
            return ["ok": false, "error": error.localizedDescription]
        }
    }

    /// 取消在途请求
    func cancel(id: Int) {
        lock.lock()
        let task = tasks.removeValue(forKey: id)
        lock.unlock()
        task?.cancel()
    }

    /// 代理设置变了就重建 session
    private func currentSession() -> URLSession {
        let configured = ProxyConfiguration.current()

        lock.lock()
        defer { lock.unlock() }
        if configured != proxy {
            proxy = configured
            session.invalidateAndCancel()
            session = Self.makeSession(proxy: configured)
        }
        return session
    }

    private func perform(_ request: URLRequest, id: Int, session: URLSession) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { [weak self] data, response, error in
                self?.forget(id: id)
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data ?? Data(), response ?? URLResponse()))
                }
            }
            lock.lock()
            tasks[id] = task
            lock.unlock()
            task.resume()
        }
    }

    private static func makeSession(proxy: ProxyConfiguration?) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"
        ]
        if let proxy {
            configuration.connectionProxyDictionary = proxy.connectionProxyDictionary
        }
        return URLSession(configuration: configuration)
    }

    private func forget(id: Int) {
        lock.lock()
        tasks.removeValue(forKey: id)
        lock.unlock()
    }

    private static func flatten(_ response: HTTPURLResponse?) -> [String: String] {
        guard let response else { return [:] }
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            headers[String(describing: name)] = String(describing: value)
        }
        return headers
    }
}
