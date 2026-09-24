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
    async fetchRejects() {
        try {
            // 非法协议：不需要真实网络即可验证 fetch 的错误路径
            await fetch("ibreeze-invalid://x");
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
    },
    async cryptoRoundTrip() {
        return {
            // createHash 走 __crypto_*_bytes 同步钩子，hmacSha256 走 bridge 异步路由
            digest: crypto.createHash("sha256").update("hello").digest("hex"),
            hmac: await crypto.hmacSha256("key", "hello"),
            randomLength: crypto.randomBytes(8).length,
            uuidLength: crypto.randomUUID().length
        };
    }
};
"""#

@Suite("插件运行时", .timeLimit(.minutes(2)))
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

/// 只在 Node 侧也能复现的沙箱：`Tools/plugin-js-harness.mjs` 覆盖同一批断言
@Suite("插件 Web 运行时", .timeLimit(.minutes(2)))
struct PluginWebRuntimeTests {
    @Test("Web 运行时、定时器与二进制链路")
    func webRuntime() async throws {
        let pluginID = UUID().uuidString
        let runtime = PluginRuntime(pluginID: pluginID, host: PluginHostBridge(pluginID: pluginID))
        try await runtime.load(bundle: runtimeBundle)

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

        let fetchResult = try await runtime.invokeObject(fnPath: "fetchRejects")
        #expect(fetchResult["failed"] as? Bool == true)

        let timer = try await runtime.invokeObject(fnPath: "timerDelay")
        let elapsed = timer["elapsed"] as? Double ?? 0
        #expect(elapsed >= 25, "定时器没有真正等待，elapsed=\(elapsed)")

        let data = try await runtime.invokeData(fnPath: "binary")
        #expect(Array(data) == [1, 2, 3, 4])

        let crypto = try await runtime.invokeObject(fnPath: "cryptoRoundTrip")
        #expect(crypto["digest"] as? String
            == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(crypto["hmac"] as? String
            == "9307b3b915efb5171ff14d8cb55fbcc798c6c0ef1456d66ded1a6aa723a58b7b")
        #expect(crypto["randomLength"] as? Int == 8)
        #expect(crypto["uuidLength"] as? Int == 36)
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
