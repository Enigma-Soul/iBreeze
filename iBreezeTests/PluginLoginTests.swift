import Foundation
import Testing
@testable import iBreeze

/// 哔咔插件真实抛出的负载：登录表单 + 预填值。
/// 注意 JS 垫片会在后面接上调用栈，所以宿主收到的是「JSON + ` {frame ← frame}`」
private let bikaPayload = #"""
{"type":"unauthorized","source":"0a0e5858-a467-4702-994a-79e608a4589d","message":"登录过期，请重新登录","scheme":{"version":"1.0.0","type":"login","title":"哔咔登录","fields":[{"key":"account","kind":"text","label":"账号"},{"key":"password","kind":"password","label":"密码"}],"action":{"fnPath":"loginWithPassword","submitText":"登录"}},"data":{"account":"someone@example.com","password":"hunter2"}}
"""#

@Suite("插件登录契约")
struct PluginLoginTests {
    @Test("认出未授权并解出登录表单")
    func parsesChallenge() throws {
        let error = PluginError.fromPluginPayload(bikaPayload)

        guard case .unauthorized(let message, let scheme, let data) = error else {
            Issue.record("没有被识别成未授权：\(error)")
            return
        }

        #expect(message == "登录过期，请重新登录")
        #expect(scheme?["type"]?.stringValue == "login")
        #expect(scheme?["title"]?.stringValue == "哔咔登录")
        #expect(scheme?["action"]?["fnPath"]?.stringValue == "loginWithPassword")

        let fields = try #require(scheme?["fields"]?.arrayValue)
        #expect(fields.count == 2)
        #expect(fields[0]["key"]?.stringValue == "account")
        #expect(fields[1]["kind"]?.stringValue == "password")

        #expect(data?["account"]?.stringValue == "someone@example.com")
    }

    /// 垫片会把 ` {frame ← frame}` 接在后面，直接 JSON.parse 整串会失败
    @Test("容忍 JS 垫片接上的调用栈")
    func toleratesStackSuffix() {
        let mangled = bikaPayload + " {e_ (eval at __loadBundle), <anonymous>:3:46765 ← processTicksAndRejections}"

        guard case .unauthorized(let message, let scheme, _) = PluginError.fromPluginPayload(mangled) else {
            Issue.record("带调用栈的负载没有被识别")
            return
        }

        #expect(message == "登录过期，请重新登录")
        #expect(scheme?["title"]?.stringValue == "哔咔登录")
    }

    @Test("字符串里的大括号不影响切分")
    func ignoresBracesInsideStrings() {
        let payload = #"{"type":"unauthorized","message":"请先 {重新} 登录","scheme":{"type":"login"},"data":{}}"#

        guard case .unauthorized(let message, _, _) = PluginError.fromPluginPayload(payload) else {
            Issue.record("括号在字符串里时切分错了")
            return
        }

        #expect(message == "请先 {重新} 登录")
    }

    @Test("只有 scheme 没写 type 也认")
    func acceptsSchemeWithoutType() {
        let payload = #"{"message":"请登录","scheme":{"type":"login","title":"登录"}}"#

        guard case .unauthorized = PluginError.fromPluginPayload(payload) else {
            Issue.record("缺少 type 时没有兜住")
            return
        }
    }

    @Test("普通错误原样保留")
    func keepsOrdinaryErrors() {
        for payload in ["插件内部错误", "", "解析失败 {第 3 行}", #"{"type":"other","message":"x"}"#] {
            guard case .pluginThrew(let kept) = PluginError.fromPluginPayload(payload) else {
                Issue.record("被误判成未授权：\(payload)")
                return
            }
            #expect(kept == payload)
        }
    }

    @Test("描述沿用插件给的话术")
    func keepsMessage() {
        #expect(PluginError.unauthorized(message: "登录过期，请重新登录", scheme: nil, data: nil)
            .errorDescription == "登录过期，请重新登录")
    }
}

/// 走一遍真实的运行时：插件抛错 → JS 垫片接栈 → 宿主解回结构化错误
@Suite("插件登录链路", .timeLimit(.minutes(2)))
struct PluginLoginRuntimeTests {
    private static let bundle = #"""
    module.exports = {
        async unauthorized() {
            throw new Error(JSON.stringify({
                type: "unauthorized",
                source: "test-plugin",
                message: "登录过期，请重新登录",
                scheme: {
                    version: "1.0.0",
                    type: "login",
                    title: "测试登录",
                    fields: [{ key: "account", kind: "text", label: "账号" }],
                    action: { fnPath: "loginWithPassword", submitText: "登录" }
                },
                data: { account: "saved" }
            }));
        }
    };
    """#

    @Test("异步抛错也能解成未授权")
    func asyncThrowBecomesUnauthorized() async throws {
        let pluginID = UUID().uuidString
        let runtime = PluginRuntime(pluginID: pluginID, host: PluginHostBridge(pluginID: pluginID))
        try await runtime.load(bundle: Self.bundle)

        do {
            _ = try await runtime.invoke(fnPath: "unauthorized")
            Issue.record("没有抛错")
        } catch let error as PluginError {
            guard case .unauthorized(let message, let scheme, let data) = error else {
                Issue.record("拿到的是：\(error)")
                return
            }
            #expect(message == "登录过期，请重新登录")
            #expect(scheme?["title"]?.stringValue == "测试登录")
            #expect(data?["account"]?.stringValue == "saved")
        }
    }
}
