import Foundation

/// 插件的 setTimeout / setInterval 宿主实现。
///
/// 与 Breeze 的约定（见 `00_bootstrap.js`）：
/// - `__timer_start_evented(delayMs, isInterval)` 同步返回 `{"ok":true,"id":n}`
/// - 到点后宿主调用 JS 的 `__host_runtime_timer_complete(hostId, payload)`
///   payload 为 `{"kind":"interval"}` 时表示重复定时器，宿主需继续计时
final class PluginTimerCenter: @unchecked Sendable {
    /// 定时时长上限，与 Breeze 的 24 小时钳制一致
    private static let maxDelayMs = 24 * 60 * 60 * 1000

    private let lock = NSLock()
    private var timers: [Int: DispatchSourceTimer] = [:]
    private var nextID = 1
    private var fire: (@Sendable (Int, String) -> Void)?

    init() {}

    /// 设置到点回调（需在启动任何定时器之前设置），实现方需保证在 JS 队列上执行
    func setFireHandler(_ handler: @escaping @Sendable (Int, String) -> Void) {
        lock.lock()
        fire = handler
        lock.unlock()
    }

    /// 启动定时器，返回 Breeze 约定的 JSON 结果
    func start(delayMs: Int, isInterval: Bool) -> String {
        let id = allocateID()
        let delay = max(0, min(delayMs, Self.maxDelayMs))

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(
            deadline: .now() + .milliseconds(delay),
            repeating: isInterval ? .milliseconds(delay) : .never
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if !isInterval { self.drop(id: id) }

            self.lock.lock()
            let handler = self.fire
            self.lock.unlock()
            handler?(id, isInterval ? #"{"kind":"interval"}"# : "{}")
        }

        lock.lock()
        timers[id] = timer
        lock.unlock()

        timer.resume()
        return #"{"ok":true,"id":\#(id)}"#
    }

    /// 取消定时器
    func drop(id: Int) {
        lock.lock()
        let timer = timers.removeValue(forKey: id)
        lock.unlock()
        timer?.cancel()
    }

    /// 运行时销毁时清理全部定时器
    func cancelAll() {
        lock.lock()
        let all = timers.values
        timers.removeAll()
        lock.unlock()
        all.forEach { $0.cancel() }
    }

    private func allocateID() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let id = nextID
        nextID += 1
        return id
    }
}
