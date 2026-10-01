import Foundation

/// 一次 `fnPath` 调用的等待者登记表。
///
/// JS 侧只有一个 `__nativeInvokeResolve` 入口，回调必须带句柄才能找回自己的等待者；
/// 否则并发调用（阅读页一次预取 7 页、列表里十几张封面）会互相顶掉回调，
/// 先发出的那些永远拿不到结果。
final class PluginInvocationRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [Int: JSInvocationWaiter] = [:]
    private var nextID = 0

    func register() -> (id: Int, waiter: JSInvocationWaiter) {
        let waiter = JSInvocationWaiter()

        lock.lock()
        nextID += 1
        let id = nextID
        waiters[id] = waiter
        lock.unlock()

        return (id, waiter)
    }

    /// 回传结果并注销；重复回传或句柄未知都当作无事发生
    func finish(id: Int, result: Result<String, Error>) {
        lock.lock()
        let waiter = waiters.removeValue(forKey: id)
        lock.unlock()

        waiter?.finish(result)
    }

    /// 调用在拿到结果前就失败了（如运行时未装载），清了避免泄漏
    func remove(id: Int) {
        lock.lock()
        waiters.removeValue(forKey: id)
        lock.unlock()
    }

    /// 运行时被替换或销毁：旧上下文不会再回传，等待者必须报错而不是一直挂着
    func failAll(with error: Error) {
        lock.lock()
        let pending = Array(waiters.values)
        waiters.removeAll()
        lock.unlock()

        for waiter in pending {
            waiter.finish(.failure(error))
        }
    }
}
