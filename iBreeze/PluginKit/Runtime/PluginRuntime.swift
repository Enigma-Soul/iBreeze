import Foundation
import JavaScriptCore
import os

/// 单个插件的 JavaScript 运行时。
///
/// JSContext 被约束在一条串行队列上：插件执行不占用主线程，宿主能力通过
/// `bridge` 路由异步回调回 JS。
final class PluginRuntime: @unchecked Sendable {
    private let executor: PluginRuntimeThread
    private let host: PluginHostBridge
    private let timers = PluginTimerCenter()
    private let logger = Logger(subsystem: "com.enigma-soul.ibreeze", category: "PluginRuntime")
    private var context: JSContext?

    init(pluginID: String, host: PluginHostBridge) {
        self.host = host
        executor = PluginRuntimeThread(name: "com.enigma-soul.ibreeze.plugin.\(pluginID)")
        timers.setFireHandler { [weak self] hostID, payload in
            self?.deliverTimerComplete(hostID: hostID, payload: payload)
        }
    }

    /// 载入插件 bundle，重建运行时（模块级状态不会保留）
    func load(bundle: String) async throws {
        let script = try PluginJSLayer.injectionScript()

        try await run { [self] in
            timers.cancelAll()
            context = nil

            let context = try Self.makeContext()
            installNativeFunctions(on: context)
            context.evaluateScript(script)
            try Self.throwIfException(context)
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

    /// 调用并解码为指定类型
    func invoke<T: Decodable>(_ type: T.Type, fnPath: String, payloadJSON: String = "{}") async throws -> T {
        let json = try await invoke(fnPath: fnPath, payloadJSON: payloadJSON)
        guard let data = json.data(using: .utf8) else {
            throw PluginError.invalidPayload("插件返回值不是合法 UTF-8")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 调用并返回原始 JSON 对象，字段缺失时由调用方兜底
    func invokeObject(fnPath: String, payloadJSON: String = "{}") async throws -> [String: Any] {
        let json = try await invoke(fnPath: fnPath, payloadJSON: payloadJSON)
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw PluginError.pluginThrew("插件返回值不是 JSON 对象")
        }
        return object
    }

    /// 调用返回二进制的 `fnPath`（如 `fetchImageBytes`）
    func invokeData(fnPath: String, payloadJSON: String = "{}") async throws -> Data {
        let json = try await invoke(fnPath: fnPath, payloadJSON: payloadJSON)
        return try Self.decodeBinary(json)
    }

    /// 销毁运行时
    func shutdown() async {
        try? await run { [self] in
            timers.cancelAll()
            context = nil
        }
        executor.stop()
    }

    // MARK: - 宿主函数注入

    private func installNativeFunctions(on context: JSContext) {
        installHostHooks(on: context)
        installTimerHooks(on: context)

        let nativeLog: @convention(block) (String, String) -> Void = { [weak self] level, message in
            self?.logger.debug("[\(level, privacy: .public)] \(message, privacy: .public)")
        }
        context.setObject(nativeLog, forKeyedSubscript: "__nativeLog" as NSString)
    }

    /// `bridge` 的两条通路：异步 `call` 与同步 `callSync`
    private func installHostHooks(on context: JSContext) {
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
    }

    /// setTimeout / setInterval 的宿主实现
    private func installTimerHooks(on context: JSContext) {
        let timerStart: @convention(block) (NSNumber, NSNumber) -> String = { [weak self] delayMs, isInterval in
            guard let self else { return #"{"ok":false,"error":"运行时已销毁"}"# }
            return self.timers.start(delayMs: delayMs.intValue, isInterval: isInterval.intValue != 0)
        }
        context.setObject(timerStart, forKeyedSubscript: "__nativeTimerStart" as NSString)

        let timerDrop: @convention(block) (NSNumber) -> Void = { [weak self] hostID in
            self?.timers.drop(id: hostID.intValue)
        }
        context.setObject(timerDrop, forKeyedSubscript: "__nativeTimerDrop" as NSString)
    }

    private func handleHostCall(id: Int, route: String, argsJSON: String) async {
        do {
            resolve(id: id, outcome: .success(try await host.dispatch(route: route, argsJSON: argsJSON)))
        } catch {
            resolve(id: id, outcome: .failure(error))
        }
    }

    /// 定时器到点：回到 JS 队列上触发插件的回调
    private func deliverTimerComplete(hostID: Int, payload: String) {
        onContext { context in
            context.objectForKeyedSubscript("__host_runtime_timer_complete")?
                .call(withArguments: [hostID, payload])
        }
    }

    private func resolve(id: Int, outcome: Result<String, Error>) {
        onContext { context in
            let arguments: [Any]
            switch outcome {
            case .success(let payload): arguments = [id, true, payload]
            case .failure(let error): arguments = [id, false, error.localizedDescription]
            }
            context.objectForKeyedSubscript("__nativeCallResolve")?.call(withArguments: arguments)
        }
    }

    /// 在 JS 线程上、且运行时仍然存活时执行一段操作
    private func onContext(_ body: @escaping @Sendable (JSContext) -> Void) {
        executor.submit { [weak self] in
            guard let self, let context = self.context else { return }
            body(context)
        }
    }

    // MARK: - 队列与上下文

    private func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            executor.submit {
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

    /// 解出 JS 侧包装的二进制信封 `{ "__ibreezeBinary": "<base64>" }`
    private static func decodeBinary(_ json: String) throws -> Data {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base64 = object["__ibreezeBinary"] as? String,
              let bytes = Data(base64Encoded: base64)
        else {
            throw PluginError.pluginThrew("插件没有返回二进制数据")
        }
        return bytes
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
