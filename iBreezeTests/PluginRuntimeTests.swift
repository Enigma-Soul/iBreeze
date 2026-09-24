import Foundation
import Testing
@testable import iBreeze

/// 一份最小插件 bundle，用来验证「加载 → 调用 fnPath → 宿主路由」整条链路
private let sampleBundle = #"""
module.exports = {
    getInfo() {
        return { name: "测试插件", uuid: "test-plugin", version: "0.0.1" };
    },
    async searchComic(payload) {
        await bridge.call("cache.set", "last-keyword", payload.keyword || "");
        const cached = await bridge.call("cache.get", "last-keyword", null);
        return {
            source: "test-plugin",
            items: [{ id: "1", source: "test-plugin", title: cached }],
            paging: { page: payload.page || 1, hasReachedMax: true }
        };
    },
    syncRoundTrip() {
        bridge.callSync("cache.set.sync", "sync-key", { value: 42 });
        return bridge.callSync("cache.get.sync", "sync-key", null);
    },
    boom() {
        throw new Error("插件内部错误");
    }
};
"""#

@Suite("插件运行时")
struct PluginRuntimeTests {
    private func makeRuntime() async throws -> PluginRuntime {
        let pluginID = UUID().uuidString
        let runtime = PluginRuntime(pluginID: pluginID, host: PluginHostBridge(pluginID: pluginID))
        try await runtime.load(bundle: sampleBundle)
        return runtime
    }

    @Test("调用 getInfo 返回插件信息")
    func getInfo() async throws {
        let runtime = try await makeRuntime()
        let info = try await runtime.invoke(PluginManifest.self, fnPath: "getInfo")

        #expect(info.name == "测试插件")
        #expect(info.uuid == "test-plugin")
    }

    @Test("bridge.call 异步路由往返")
    func asyncBridgeRoundTrip() async throws {
        let runtime = try await makeRuntime()
        let result = try await runtime.invoke(
            ComicPagedList.self,
            fnPath: "searchComic",
            payloadJSON: #"{"keyword":"海贼","page":2}"#
        )

        #expect(result.resolvedItems.first?.title == "海贼")
        #expect(result.resolvedPaging?.page == 2)
    }

    @Test("bridge.callSync 同步路由往返")
    func syncBridgeRoundTrip() async throws {
        let runtime = try await makeRuntime()
        let json = try await runtime.invoke(fnPath: "syncRoundTrip")

        #expect(json.contains("42"))
    }

    @Test("插件抛错转成 Swift 错误")
    func pluginThrownError() async throws {
        let runtime = try await makeRuntime()

        await #expect(throws: PluginError.self) {
            try await runtime.invoke(fnPath: "boom")
        }
    }

    @Test("未实现的 fnPath 报错")
    func missingFunction() async throws {
        let runtime = try await makeRuntime()

        await #expect(throws: PluginError.self) {
            try await runtime.invoke(fnPath: "notImplemented")
        }
    }
}

@Suite("简繁转换")
struct ChineseConverterTests {
    @Test("按 opencc 配置名转换")
    func convert() {
        #expect(ChineseConverter.convert("繁體字", config: "t2s.json") == "繁体字")
        #expect(ChineseConverter.convert("简体字", config: "s2t.json") == "簡體字")
        #expect(ChineseConverter.convert("unknown", config: "不存在.json") == "unknown")
    }
}
