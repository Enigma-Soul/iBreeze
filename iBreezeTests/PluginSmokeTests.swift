import Foundation
import Testing
@testable import iBreeze

/// 真实插件冒烟测试：走网络下载 Breeze 生态的现成插件并跑通调用链。
///
/// 默认不跑，CI 通过 `TEST_RUNNER_IBREEZE_SMOKE=1` 打开。
/// 它覆盖的是最容易出问题的地方：jsDelivr 下载、真实 bundle 在 JavaScriptCore
/// 上装载、`getInfo` 契约解析，以及插件自身逻辑与错误回传。
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

    /// 安装一次跑多个断言，避免重复下载
    private func installEhentai() async throws -> (PluginSource, InstalledPlugin) {
        let store = PluginStore(directory: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ibreeze-smoke-\(UUID().uuidString)"))
        let installer = PluginInstaller(store: store)
        let remote = try JSONDecoder().decode(RemotePlugin.self, from: Data(Self.ehentai.utf8))

        let plugin = try await installer.install(remote)
        let source = PluginSource(plugin: plugin)
        try await source.load(bundle: try store.bundle(for: plugin.uuid))
        return (source, plugin)
    }

    @Test("下载安装真实插件并解析 getInfo", .timeLimit(.minutes(3)))
    func installAndInspect() async throws {
        let (source, plugin) = try await installEhentai()
        defer { Task { await source.shutdown() } }

        let remote = try JSONDecoder().decode(RemotePlugin.self, from: Data(Self.ehentai.utf8))
        #expect(plugin.uuid == remote.manifest.uuid)
        #expect(!plugin.version.isEmpty)
        #expect(!plugin.functions.isEmpty, "getInfo 没有返回功能入口")

        let info = try await source.info()
        #expect(info.uuid == remote.manifest.uuid)
        #expect(!info.name.isEmpty)

        // 插件的列表入口应能解析成列表场景（body.request.fnPath）
        let scene = try #require(info.function?.first?.action.payload?.scene)
        #expect(!scene.body.request.fnPath.isEmpty)

        // 插件自身的域名白名单会拒绝非图源地址，说明它的 JS 逻辑确实执行了
        await #expect(throws: PluginError.self) {
            _ = try await source.imageBytes(url: "https://example.com/")
        }
    }

    /// 单纯走图片抓取：只经过「fetch → Uint8Array」，
    /// 用来把问题范围缩到插件自己的请求包装（列表功能还叠了 axios 与解析）
    @Test(
        "抓取真实图片字节",
        .enabled(if: ProcessInfo.processInfo.environment["IBREEZE_SMOKE_NETWORK"] == "1"),
        .timeLimit(.minutes(2))
    )
    func fetchRealImage() async throws {
        let (source, _) = try await installEhentai()
        defer { Task { await source.shutdown() } }

        let bytes = try await source.imageBytes(url: "https://e-hentai.org/favicon.ico")
        #expect(bytes.count > 0, "没有拿到图片字节")
    }

    /// 联网抓真实列表、详情与阅读快照：站点可能对 CI 机房 IP 不友好，单独用环境变量控制
    @Test(
        "列表到阅读的完整链路",
        .enabled(if: ProcessInfo.processInfo.environment["IBREEZE_SMOKE_NETWORK"] == "1"),
        .timeLimit(.minutes(4))
    )
    func fetchRealList() async throws {
        let (source, _) = try await installEhentai()
        defer { Task { await source.shutdown() } }

        let info = try await source.info()
        let scene = try #require(info.function?.first?.action.payload?.scene)

        // 1. 列表
        let list = try await source.pagedList(
            fnPath: scene.body.request.fnPath,
            page: 1,
            core: scene.body.request.core,
            extern: scene.body.request.extern
        )
        #expect(!list.resolvedItems.isEmpty, "列表没有返回任何条目")
        let item = try #require(list.resolvedItems.first)
        #expect(!item.id.isEmpty)
        #expect(!item.title.isEmpty)

        // 2. 详情与章节
        let detail = try await source.comicDetail(comicID: item.id)
        #expect(detail.data?.normal?.comicInfo?.title?.isEmpty == false, "详情没有标题")
        let chapters = try #require(detail.data?.normal?.eps)
        #expect(!chapters.isEmpty, "详情没有章节")

        // 3. 阅读快照里的图片列表
        let snapshot = try await source.readSnapshot(
            comicID: item.id,
            chapterID: chapters[0].resolvedRequestId
        )
        let pages = try #require(snapshot.data?.chapter?.pages)
        #expect(!pages.isEmpty, "章节没有返回图片")
        #expect(pages[0].url?.isEmpty == false, "图片地址为空")
    }
}
