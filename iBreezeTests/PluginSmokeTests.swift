import Foundation
import Testing
@testable import iBreeze

/// 真实插件冒烟测试：走网络下载 Breeze 生态的现成插件并跑通调用链。
///
/// 默认不跑（本地无网络或不希望依赖外网），CI 通过 `TEST_RUNNER_IBREEZE_SMOKE=1` 打开。
/// 它验证的是最容易出问题的地方：jsDelivr 下载、真实 bundle 在 JavaScriptCore 上装载、
/// `getInfo` 契约解析，以及 `fetchImageBytes` 的二进制回传。
@Suite("真实插件冒烟", .enabled(if: ProcessInfo.processInfo.environment["IBREEZE_SMOKE"] == "1"))
struct PluginSmokeTests {
    private static let ehentai = #"""
    {
      "repo": "deretame/Breeze-plugin-ehentai",
      "manifest": {
        "name": "e-hentai",
        "uuid": "dba2a6cf-c495-4416-accf-c29263ab4016",
        "npmName": "breeze-plugin-ehentai",
        "updateUrl": "https://api.github.com/repos/deretame/Breeze-plugin-ehentai/releases/latest"
      }
    }
    """#

    private func makeStore() -> PluginStore {
        PluginStore(directory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ibreeze-smoke-\(UUID().uuidString)"))
    }

    @Test("下载并安装真实插件，再跑通 getInfo 与图片下载", .timeLimit(.minutes(3)))
    func installRealPlugin() async throws {
        let store = makeStore()
        let installer = PluginInstaller(store: store)
        let remote = try JSONDecoder().decode(RemotePlugin.self, from: Data(Self.ehentai.utf8))

        let plugin = try await installer.install(remote)
        #expect(plugin.uuid == remote.manifest.uuid)
        #expect(!plugin.version.isEmpty)
        #expect(!plugin.functions.isEmpty, "getInfo 没有返回功能入口")

        // 用安装好的 bundle 建常驻运行时，验证真实插件的契约调用
        let source = PluginSource(plugin: plugin)
        try await source.load(bundle: try store.bundle(for: plugin.uuid))

        let info = try await source.info()
        #expect(info.uuid == remote.manifest.uuid)
        #expect(!info.name.isEmpty)

        // fetchImageBytes 是通用抓取：拿一个稳定站点验证「插件 fetch → 宿主二进制回传」
        let bytes = try await source.imageBytes(url: "https://example.com/")
        #expect(bytes.count > 0, "图片字节为空")

        await source.shutdown()
    }
}
