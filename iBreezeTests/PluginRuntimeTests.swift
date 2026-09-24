import Foundation
import Testing
@testable import iBreeze

/// 最小插件 bundle，用来验证「加载 → 调用 fnPath → 宿主路由」整条链路
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

/// 校验 Web 运行时是否就位，并覆盖二进制与定时器链路
private let runtimeBundle = #"""
module.exports = {
    runtimeGlobals() {
        return {
            hasURL: typeof URL === "function",
            hasHeaders: typeof Headers === "function",
            hasFetch: typeof fetch === "function",
            hasResponse: typeof Response === "function",
            hasAbortController: typeof AbortController === "function",
            hasTextEncoder: typeof TextEncoder === "function",
            hasStructuredClone: typeof structuredClone === "function",
            hasFormData: typeof FormData === "function",
            hasBlob: typeof Blob === "function",
            hasBuffer: typeof Buffer === "function",
            hasTemporal: typeof Temporal !== "undefined",
            pathname: new URL("https://example.com/a/b?x=1").pathname,
            query: new URLSearchParams("a=1&b=2").get("b"),
            base64: bytesToBase64(new TextEncoder().encode("hello")),
            decoded: new TextDecoder().decode(bytesFromBase64("aGVsbG8="))
        };
    },
    async fetchUnreachable() {
        try {
            await fetch("http://127.0.0.1:1/unreachable");
            return { failed: false, message: "" };
        } catch (error) {
            return { failed: true, message: String((error && error.message) || error) };
        }
    },
    async timerDelay() {
        const started = Date.now();
        await new Promise((resolve) => setTimeout(resolve, 30));
        return { elapsed: Date.now() - started };
    },
    binary() {
        return new Uint8Array([1, 2, 3, 4]);
    }
};
"""#

@Suite("插件运行时")
struct PluginRuntimeTests {
    private func makeRuntime(bundle: String = sampleBundle) async throws -> PluginRuntime {
        let pluginID = UUID().uuidString
        let runtime = PluginRuntime(pluginID: pluginID, host: PluginHostBridge(pluginID: pluginID))
        try await runtime.load(bundle: bundle)
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

@Suite("插件 Web 运行时")
struct PluginWebRuntimeTests {
    private func makeRuntime() async throws -> PluginRuntime {
        let pluginID = UUID().uuidString
        let runtime = PluginRuntime(pluginID: pluginID, host: PluginHostBridge(pluginID: pluginID))
        try await runtime.load(bundle: runtimeBundle)
        return runtime
    }

    @Test("注入的全局对象齐备")
    func runtimeGlobals() async throws {
        let runtime = try await makeRuntime()
        let globals = try await runtime.invokeObject(fnPath: "runtimeGlobals")

        for key in [
            "hasURL", "hasHeaders", "hasFetch", "hasResponse", "hasAbortController",
            "hasTextEncoder", "hasStructuredClone", "hasFormData", "hasBlob",
            "hasBuffer", "hasTemporal"
        ] {
            #expect(globals[key] as? Bool == true, "缺少全局对象：\(key)")
        }
        #expect(globals["pathname"] as? String == "/a/b")
        #expect(globals["query"] as? String == "2")
        #expect(globals["base64"] as? String == "aGVsbG8=")
        #expect(globals["decoded"] as? String == "hello")
    }

    @Test("fetch 失败时插件收到异常")
    func fetchUnreachable() async throws {
        let runtime = try await makeRuntime()
        let result = try await runtime.invokeObject(fnPath: "fetchUnreachable")

        #expect(result["failed"] as? Bool == true)
    }

    @Test("定时器由宿主驱动")
    func timerDelay() async throws {
        let runtime = try await makeRuntime()
        let result = try await runtime.invokeObject(fnPath: "timerDelay")

        let elapsed = result["elapsed"] as? Double ?? 0
        #expect(elapsed >= 25, "定时器没有真正等待，elapsed=\(elapsed)")
    }

    @Test("返回二进制时走二进制信封")
    func binaryResult() async throws {
        let runtime = try await makeRuntime()
        let data = try await runtime.invokeData(fnPath: "binary")

        #expect(Array(data) == [1, 2, 3, 4])
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
