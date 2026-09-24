import Foundation
import JavaScriptCore
import os

/// 单个插件的 JavaScript 运行时。
///
/// JSContext 被约束在一条串行队列上：插件执行不会占用主线程，宿主能力通过
/// `bridge` 路由异步回调回 JS。
final class PluginRuntime: @unchecked Sendable {
    private let queue: DispatchQueue
    private let host: PluginHostBridge
    private let logger = Logger(subsystem: "com.enigma-soul.ibreeze", category: "PluginRuntime")
    private var context: JSContext?

    init(pluginID: String, host: PluginHostBridge) {
        self.host = host
        self.queue = DispatchQueue(label: "com.enigma-soul.ibreeze.plugin.\(pluginID)")
    }

    /// 载入插件 bundle，重建运行时（模块级状态不会保留）
    func load(bundle: String) async throws {
        try await run { [self] in
            let context = try Self.makeContext()
            installNativeFunctions(on: context)
            context.evaluateScript(RuntimeGlue.source)
            context.objectForKeyedSubscript("__loadBundle")?.call(withArguments: [bundle])
            try Self.throwIfException(context)
            self.context = context
        }
    }

    /// 调用插件的某个 `fnPath`，返回结果的 JSON 文本
    func invoke(fnPath: String, payloadJSON: String = "{}") async throws -> String {
        let waiter = JSInvocationWaiter()

        try await run { [self] in
            guard let context else { throw PluginError.runtimeNotLoaded }

            let resolve: @convention(block) (Bool, String) -> Void = { ok, payload in
                waiter.finish(ok ? .success(payload) : .failure(PluginError.pluginThrew(payload)))
            }
            context.setObject(resolve, forKeyedSubscript: "__nativeInvokeResolve" as NSString)

            context.objectForKeyedSubscript("__invokePlugin")?.call(withArguments: [fnPath, payloadJSON])
            try Self.throwIfException(context)
        }

        return try await waiter.wait()
    }

    /// 销毁运行时
    func shutdown() async {
        try? await run { [self] in context = nil }
    }

    // MARK: - 宿主函数注入

    private func installNativeFunctions(on context: JSContext) {
        let nativeCall: @convention(block) (NSNumber, String, String) -> Void = { [weak self] id, route, argsJSON in
            guard let self else { return }
            let callID = id.intValue
            Task { await self.handleHostCall(id: callID, route: route, argsJSON: argsJSON) }
        }
        context.setObject(nativeCall, forKeyedSubscript: "__nativeCall" as NSString)

        let nativeCallSync: @convention(block) (String, String) -> String = { [weak self] route, argsJSON in
            guard let self else { return #"{"ok":false,"payload":"运行时已销毁"}"# }
            return self.host.dispatchSync(route: route, argsJSON: argsJSON)
        }
        context.setObject(nativeCallSync, forKeyedSubscript: "__nativeCallSync" as NSString)

        let nativeLog: @convention(block) (String, String) -> Void = { [weak self] level, message in
            self?.logger.debug("[\(level, privacy: .public)] \(message, privacy: .public)")
        }
        context.setObject(nativeLog, forKeyedSubscript: "__nativeLog" as NSString)
    }

    private func handleHostCall(id: Int, route: String, argsJSON: String) async {
        let outcome: Result<String, Error>
        do {
            outcome = .success(try await host.dispatch(route: route, argsJSON: argsJSON))
        } catch {
            outcome = .failure(error)
        }
        resolve(id: id, outcome: outcome)
    }

    private func resolve(id: Int, outcome: Result<String, Error>) {
        queue.async { [weak self] in
            guard let self, let context = self.context else { return }
            switch outcome {
            case .success(let payload):
                context.objectForKeyedSubscript("__nativeCallResolve")?.call(withArguments: [id, true, payload])
            case .failure(let error):
                context.objectForKeyedSubscript("__nativeCallResolve")?
                    .call(withArguments: [id, false, error.localizedDescription])
            }
        }
    }

    // MARK: - 队列与上下文

    private func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func makeContext() throws -> JSContext {
        guard let context = JSContext() else { throw PluginError.runtimeUnavailable }
        context.exceptionHandler = { _, exception in
            // 异常由 throwIfException 统一转成 Swift 错误，这里只做兜底记录
            guard let exception else { return }
            Logger(subsystem: "com.enigma-soul.ibreeze", category: "PluginRuntime")
                .error("JS 异常: \(exception.toString() ?? "unknown", privacy: .public)")
        }
        return context
    }

    private static func throwIfException(_ context: JSContext) throws {
        guard let exception = context.exception else { return }
        context.exception = nil
        let message = exception.objectForKeyedSubscript("message")?.toString()
            ?? exception.toString()
            ?? "未知异常"
        throw PluginError.pluginThrew(message)
    }
}

/// 把 JS 的一次性回调桥接成 Swift async 等待
private final class JSInvocationWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var settled: Result<String, Error>?

    func wait() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let settled {
                lock.unlock()
                continuation.resume(with: settled)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard let continuation else {
            settled = result
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}
