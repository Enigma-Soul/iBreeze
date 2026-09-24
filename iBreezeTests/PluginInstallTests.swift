import Foundation
import Testing
@testable import iBreeze

/// 可安装的测试插件：`getInfo` 是唯一的权威信息来源
private let installableBundle = #"""
module.exports = {
    getInfo() {
        return {
            name: "测试源",
            uuid: "test-source",
            version: "1.0.0",
            npmName: "test-source",
            describe: "单元测试用",
            function: []
        };
    }
};
"""#

/// 换个 uuid 的版本，用来验证更新时的 uuid 校验
private let otherSourceBundle = #"""
module.exports = {
    getInfo() {
        return { name: "另一个源", uuid: "other-source", version: "2.0.0", npmName: "other-source" };
    }
};
"""#

/// 按 URL 返回预置内容的下载桩
private struct StubDownloader: PluginDownloading {
    var responses: [String: Data]

    func data(from url: URL) async throws -> Data {
        guard let data = responses[url.absoluteString] else {
            throw PluginInstallError.downloadFailed(url.absoluteString, 404)
        }
        return data
    }
}

private func makeStore() -> PluginStore {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ibreeze-tests-\(UUID().uuidString)")
    return PluginStore(directory: directory)
}

private func remotePlugin(json: String) throws -> RemotePlugin {
    try JSONDecoder().decode(RemotePlugin.self, from: Data(json.utf8))
}

@Suite("插件版本比较")
struct PluginVersionTests {
    @Test("按段比较版本号")
    func compare() {
        #expect(PluginVersion.isNewer("1.0.1", than: "1.0.0"))
        #expect(PluginVersion.isNewer("v2.0", than: "1.9.9"))
        #expect(PluginVersion.isNewer("1.10.0", than: "1.9.0"))
        #expect(!PluginVersion.isNewer("1.0.0", than: "1.0.0"))
        #expect(!PluginVersion.isNewer("0.9.9", than: "1.0.0"))
    }
}

@Suite("插件存储")
struct PluginStoreTests {
    @Test("保存、读取与删除")
    func saveLoadRemove() throws {
        let store = makeStore()
        let manifest = try #require(
            try JSONDecoder().decode(
                PluginManifest.self,
                from: Data(#"{"name":"测试源","uuid":"test-source","version":"1.0.0"}"#.utf8)
            )
        )

        try store.save(InstalledPlugin(manifest: manifest), bundle: "module.exports = {};")
        #expect(store.installed().count == 1)
        #expect(try store.bundle(for: "test-source") == "module.exports = {};")

        // 重新打开应能读回索引
        let reopened = PluginStore(directory: store.directory)
        #expect(reopened.plugin(uuid: "test-source")?.name == "测试源")

        try store.remove(uuid: "test-source")
        #expect(store.installed().isEmpty)
        #expect(throws: (any Error).self) { try store.bundle(for: "test-source") }
    }
}

@Suite("插件安装器")
struct PluginInstallerTests {
    private static let npmURL = "https://cdn.jsdelivr.net/npm/test-source@latest/dist/test-source.bundle.cjs"

    @Test("从 npm 首镜像安装并落盘")
    func installFromNPM() async throws {
        let store = makeStore()
        let installer = PluginInstaller(
            downloader: StubDownloader(responses: [Self.npmURL: Data(installableBundle.utf8)]),
            store: store
        )
        let remote = try remotePlugin(
            json: #"{"repo":"deretame/Breeze-plugin-test","manifest":{"name":"测试源","uuid":"test-source","npmName":"test-source"}}"#
        )

        let installed = try await installer.install(remote)

        #expect(installed.uuid == "test-source")
        #expect(installed.version == "1.0.0")
        #expect(store.installed().count == 1)
        #expect(try store.bundle(for: "test-source").contains("test-source"))
    }

    @Test("npm 失败时回退到 GitHub Release")
    func fallbackToRelease() async throws {
        let store = makeStore()
        let releaseURL = "https://api.github.com/repos/x/y/releases/latest"
        let assetURL = "https://example.com/demo.bundle.cjs"
        let release = """
        {"tag_name":"1.0.0","assets":[{"name":"demo.bundle.cjs","browser_download_url":"\(assetURL)"}]}
        """
        let installer = PluginInstaller(
            downloader: StubDownloader(responses: [
                releaseURL: Data(release.utf8),
                assetURL: Data(installableBundle.utf8)
            ]),
            store: store
        )
        let remote = try remotePlugin(
            json: #"{"repo":"x/y","manifest":{"name":"测试源","uuid":"test-source","updateUrl":"https://api.github.com/repos/x/y/releases/latest"}}"#
        )

        let installed = try await installer.install(remote)

        #expect(installed.uuid == "test-source")
    }

    @Test("缺少下载通道时报错")
    func missingChannel() async throws {
        let store = makeStore()
        let installer = PluginInstaller(downloader: StubDownloader(responses: [:]), store: store)
        let remote = try remotePlugin(json: #"{"repo":"x/y","manifest":{"name":"测试源","uuid":"test-source"}}"#)

        await #expect(throws: PluginInstallError.self) {
            try await installer.install(remote)
        }
    }

    @Test("更新时 UUID 不一致会被拒绝")
    func uuidMismatch() async throws {
        let store = makeStore()
        let installer = PluginInstaller(
            downloader: StubDownloader(responses: [
                "https://cdn.jsdelivr.net/npm/other-source@latest/dist/other-source.bundle.cjs": Data(otherSourceBundle.utf8)
            ]),
            store: store
        )
        let existing = InstalledPlugin(
            manifest: try JSONDecoder().decode(
                PluginManifest.self,
                from: Data(#"{"name":"测试源","uuid":"test-source","version":"1.0.0","npmName":"other-source"}"#.utf8)
            )
        )

        await #expect(throws: PluginInstallError.self) {
            try await installer.update(existing)
        }
    }

    @Test("版本不更新时跳过安装")
    func skipWhenUpToDate() async throws {
        let store = makeStore()
        let installer = PluginInstaller(
            downloader: StubDownloader(responses: [Self.npmURL: Data(installableBundle.utf8)]),
            store: store
        )
        let existing = InstalledPlugin(
            manifest: try JSONDecoder().decode(
                PluginManifest.self,
                from: Data(#"{"name":"测试源","uuid":"test-source","version":"1.0.0","npmName":"test-source"}"#.utf8)
            )
        )

        let updated = try await installer.update(existing)

        #expect(updated == false)
        #expect(store.installed().isEmpty)
    }
}
