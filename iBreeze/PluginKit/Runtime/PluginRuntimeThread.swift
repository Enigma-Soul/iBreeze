import Foundation

/// 承载插件 JS 的独立线程。
///
/// 用独立线程而不是 `DispatchQueue`，是为了能指定**更大的栈**：
/// JavaScriptCore 的递归深度受宿主线程栈限制，而插件普遍打包了 axios 之类的库，
/// 调用链较深时会在默认工作线程栈上抛 "Maximum call stack size exceeded"。
///
/// 线程内是一个手写的串行任务循环：保证所有 JS 都跑在同一条线程上（JSContext 要求），
/// 同时不引入 RunLoop 的生命周期问题。
final class PluginRuntimeThread: @unchecked Sendable {
    /// 16MB：远大于 GCD 工作线程的默认栈，覆盖深层调用链
    private static let stackSize = 16 * 1024 * 1024

    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var pending: [() -> Void] = []
    private var stopped = false

    init(name: String) {
        let thread = Thread { [self] in runLoop() }
        thread.name = name
        thread.stackSize = Self.stackSize
        thread.start()
    }

    /// 把任务投递到 JS 线程，按投递顺序串行执行
    func submit(_ block: @escaping () -> Void) {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        pending.append(block)
        lock.unlock()
        semaphore.signal()
    }

    /// 停止线程（运行时销毁时调用）
    func stop() {
        lock.lock()
        stopped = true
        pending.removeAll()
        lock.unlock()
        semaphore.signal()
    }

    private func runLoop() {
        while true {
            semaphore.wait()

            lock.lock()
            if stopped {
                lock.unlock()
                return
            }
            let work = pending.isEmpty ? nil : pending.removeFirst()
            lock.unlock()

            work?()
        }
    }
}
