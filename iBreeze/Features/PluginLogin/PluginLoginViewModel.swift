import Foundation
import Observation

/// 登录表单：字段完全由插件声明的 scheme 决定，宿主不写死账号/密码
@MainActor
@Observable
final class PluginLoginViewModel {
    struct Field: Identifiable {
        let key: String
        let kind: String
        let label: String
        var value: String

        var id: String { key }
        var isSecure: Bool { kind == "password" }
    }

    let pluginID: String
    /// 被动弹出时（接口报未授权）显示的原因
    let notice: String?

    private(set) var title = "登录"
    private(set) var fields: [Field] = []
    private(set) var submitText = "登录"
    private(set) var isLoading = true
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    /// 登录动作的 fnPath，由 scheme 的 action 给出
    private var actionPath: String?
    /// 退出登录的 fnPath
    private(set) var signOutPath: String?

    init(pluginID: String, notice: String? = nil) {
        self.pluginID = pluginID
        self.notice = notice
    }

    var canSubmit: Bool {
        !isSubmitting && fields.contains { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let source = try await PluginRegistry.shared.source(for: pluginID)
            let scheme = try await source.loginScheme()

            title = scheme["title"]?.stringValue ?? "登录"
            submitText = scheme["action"]?["submitText"]?.stringValue ?? "登录"
            actionPath = scheme["action"]?["fnPath"]?.stringValue

            let prefilled = try? await source.loginPrefill()
            fields = (scheme["fields"]?.arrayValue ?? []).compactMap { item in
                guard let key = item["key"]?.stringValue else { return nil }
                return Field(
                    key: key,
                    kind: item["kind"]?.stringValue ?? "text",
                    label: item["label"]?.stringValue ?? key,
                    value: prefilled?[key]?.stringValue ?? ""
                )
            }
            signOutPath = await source.signOutPath()
            errorMessage = fields.isEmpty ? "插件没有声明任何登录字段" : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func update(key: String, value: String) {
        guard let index = fields.firstIndex(where: { $0.key == key }) else { return }
        fields[index].value = value
    }

    /// 返回是否登录成功
    func submit() async -> Bool {
        guard let actionPath else {
            errorMessage = "插件没有声明登录动作"
            return false
        }

        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil

        var payload: [String: Any] = [:]
        for field in fields { payload[field.key] = field.value }

        do {
            let source = try await PluginRegistry.shared.source(for: pluginID)
            _ = try await source.perform(fnPath: actionPath, payload: payload)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 退出登录：清掉插件侧保存的会话
    func signOut() async {
        guard let signOutPath else { return }
        do {
            let source = try await PluginRegistry.shared.source(for: pluginID)
            _ = try await source.perform(fnPath: signOutPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
