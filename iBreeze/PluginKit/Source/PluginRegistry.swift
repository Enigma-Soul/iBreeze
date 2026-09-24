import Foundation
import Observation

/// 插件源注册表：管理已安装插件，按需装载常驻运行时。
///
/// UI 只跟它打交道：拿列表、装插件、取某个插件的 `PluginSource`。
@MainActor
@Observable
final class PluginRegistry {
    static let shared = PluginRegistry()

    private(set) var installed: [InstalledPlugin] = []

    private let store: PluginStore
    private let installer: PluginInstaller
    private let repository: PluginRepository
    private var sources: [String: PluginSource] = [:]

    init(
        store: PluginStore = .shared,
        installer: PluginInstaller? = nil,
        repository: PluginRepository = PluginRepository()
    ) {
        self.store = store
        self.installer = installer ?? PluginInstaller(store: store)
        self.repository = repository
        installed = store.installed()
    }

    /// 重新读取已安装列表
    func reload() {
        installed = store.installed()
    }

    /// 取插件源，必要时装载运行时；同一插件复用同一个运行时
    func source(for uuid: String) async throws -> PluginSource {
        if let existing = sources[uuid] { return existing }

        guard let plugin = store.plugin(uuid: uuid) else {
            throw PluginError.pluginThrew("插件未安装：\(uuid)")
        }
        let source = PluginSource(plugin: plugin)
        try await source.load(bundle: try store.bundle(for: uuid))
        sources[uuid] = source
        return source
    }

    /// 已装载的插件源；不会触发装载
    func cachedSource(for uuid: String) -> PluginSource? {
        sources[uuid]
    }

    /// 释放运行时（卸载或更新前调用）
    func close(uuid: String) async {
        await sources[uuid]?.shutdown()
        sources[uuid] = nil
    }

    // MARK: - 云端列表与安装

    func cloudPlugins() async throws -> [RemotePlugin] {
        try await repository.fetch()
    }

    @discardableResult
    func install(_ remote: RemotePlugin) async throws -> InstalledPlugin {
        let plugin = try await installer.install(remote)
        reload()
        return plugin
    }

    @discardableResult
    func install(bundleURL: URL) async throws -> InstalledPlugin {
        let plugin = try await installer.install(bundleURL: bundleURL)
        reload()
        return plugin
    }

    /// 检查并安装更新，返回是否真的更新了
    @discardableResult
    func update(_ plugin: InstalledPlugin) async throws -> Bool {
        let updated = try await installer.update(plugin)
        if updated {
            // 运行时里还是旧 bundle，关掉让它下次按新版本重建
            await close(uuid: plugin.uuid)
            reload()
        }
        return updated
    }

    func uninstall(_ plugin: InstalledPlugin) async throws {
        await close(uuid: plugin.uuid)
        try store.remove(uuid: plugin.uuid)
        reload()
    }
}
