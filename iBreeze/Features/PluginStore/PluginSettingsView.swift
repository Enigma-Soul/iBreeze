import SwiftUI
import Observation

/// 插件设置页 VM：字段与当前值都来自插件的 `getSettingsBundle`
@MainActor
@Observable
final class PluginSettingsViewModel {
    struct Field: Identifiable {
        var key: String
        var kind: String
        var label: String
        var callbackPath: String?
        var persists: Bool
        var options: [(label: String, value: JSONValue)]

        var id: String { key }
    }

    struct Section: Identifiable {
        var title: String
        var fields: [Field]

        var id: String { title }
    }

    private(set) var sections: [Section] = []
    private(set) var values: [String: JSONValue] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// 插件是否支持登录（声明了 `getLoginBundle`）
    private(set) var supportsLogin = false
    /// 退出登录的 fnPath，插件没导出就为 nil
    private(set) var signOutPath: String?

    private let plugin: InstalledPlugin

    init(plugin: InstalledPlugin) {
        self.plugin = plugin
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let source = try await PluginRegistry.shared.source(for: plugin.uuid)
            supportsLogin = await source.supportsLogin()
            signOutPath = supportsLogin ? await source.signOutPath() : nil

            let bundle = try await source.settingsBundle()

            values = bundle["data"]?["values"]?.objectValue ?? [:]

            sections = (bundle["scheme"]?["sections"]?.arrayValue ?? []).compactMap { section in
                guard let title = section["title"]?.stringValue else { return nil }
                return Section(
                    title: title,
                    fields: (section["fields"]?.arrayValue ?? []).compactMap(Self.makeField)
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 把插件声明的一个字段解成 `Field`
    private static func makeField(_ json: JSONValue) -> Field? {
        guard let key = json["key"]?.stringValue, let kind = json["kind"]?.stringValue else { return nil }

        let options = (json["options"]?.arrayValue ?? []).compactMap { option -> (label: String, value: JSONValue)? in
            guard let label = option["label"]?.stringValue, let value = option["value"] else { return nil }
            return (label, value)
        }

        return Field(
            key: key,
            kind: kind,
            label: json["label"]?.stringValue ?? key,
            callbackPath: json["fnPath"]?.stringValue,
            persists: json["persist"]?.anyValue as? Bool ?? true,
            options: options
        )
    }

    /// 值的展示文本。
    ///
    /// 有些插件把 `{"ok":…,"value":…}` 这种信封原样存了进来，直接显示会很难看，
    /// 这里拆一层；空值时显示空串而不是那串 JSON。
    static func displayText(for value: JSONValue?) -> String {
        guard let text = value?.stringValue else { return "" }
        guard
            let data = text.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["ok"] != nil
        else { return text }

        switch object["value"] {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        default: return ""
        }
    }

    /// 退出登录：交给插件自己清理会话（token、账号密码都归它管）
    func signOut() async {
        guard let signOutPath else { return }

        do {
            let source = try await PluginRegistry.shared.source(for: plugin.uuid)
            _ = try await source.perform(fnPath: signOutPath)
            errorMessage = nil
            ToastCenter.shared.show("已退出登录")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 值变化：先按约定持久化，再回调插件的 fnPath
    func update(field: Field, value: JSONValue) async {
        values[field.key] = value

        do {
            let source = try await PluginRegistry.shared.source(for: plugin.uuid)
            if field.persists {
                try await source.saveSetting(key: field.key, value: value)
            }
            if let callbackPath = field.callbackPath {
                try await source.notifySettingChanged(fnPath: callbackPath, key: field.key, value: value)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 插件设置页：由插件声明字段，宿主渲染并回写
struct PluginSettingsView: View {
    @State private var viewModel: PluginSettingsViewModel
    @State private var showsLogin = false
    @State private var confirmsSignOut = false
    private let plugin: InstalledPlugin

    init(plugin: InstalledPlugin) {
        self.plugin = plugin
        _viewModel = State(initialValue: PluginSettingsViewModel(plugin: plugin))
    }

    var body: some View {
        Form {
            accountSection

            if viewModel.sections.isEmpty {
                Section {
                    if viewModel.isLoading {
                        HStack {
                            ProgressView()
                            Text("正在读取插件设置")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(viewModel.errorMessage ?? "该插件没有提供设置项")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(viewModel.sections) { section in
                    Section(section.title) {
                        ForEach(section.fields) { field in
                            row(for: field)
                        }
                    }
                }
            }

            if !viewModel.sections.isEmpty, let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(plugin.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { if viewModel.sections.isEmpty { await viewModel.load() } }
        .sheet(isPresented: $showsLogin) {
            // 就地弹，而不是走根视图那份全局请求：设置页本身就在一张 sheet 上
            PluginLoginSheet(pluginID: plugin.uuid, pluginName: plugin.name)
        }
        .confirmationDialog("确定要退出登录？", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task { await viewModel.signOut() }
            }
        }
    }

    /// 支持登录的插件才有这一段
    @ViewBuilder
    private var accountSection: some View {
        if viewModel.supportsLogin {
            Section {
                Button("登录") { showsLogin = true }

                if viewModel.signOutPath != nil {
                    Button("退出登录", role: .destructive) { confirmsSignOut = true }
                }
            } header: {
                Text("账号")
            } footer: {
                Text("账号密码保存在插件自己的配置里；登录失效时宿主也会自动弹出这张表单。")
            }
        }
    }

    @ViewBuilder
    private func row(for field: PluginSettingsViewModel.Field) -> some View {
        switch field.kind {
        case "switch":
            Toggle(field.label, isOn: Binding(
                get: { viewModel.values[field.key]?.anyValue as? Bool ?? false },
                set: { newValue in
                    Task { await viewModel.update(field: field, value: .bool(newValue)) }
                }
            ))

        case "select", "choice":
            Picker(field.label, selection: Binding(
                get: { viewModel.values[field.key]?.stringValue ?? "" },
                set: { newValue in
                    Task { await viewModel.update(field: field, value: .string(newValue)) }
                }
            )) {
                ForEach(field.options, id: \.label) { option in
                    Text(option.label).tag(option.value.stringValue ?? "")
                }
            }

        default:
            SettingTextRow(
                title: field.label,
                isSecure: field.kind == "password",
                initialValue: PluginSettingsViewModel.displayText(for: viewModel.values[field.key])
            ) { text in
                Task { await viewModel.update(field: field, value: .string(text)) }
            }
        }
    }
}

/// 文本类设置项：编辑时先写草稿，回车或离开页面才提交，
/// 免得每敲一个字就回调一次插件。
private struct SettingTextRow: View {
    let title: String
    let isSecure: Bool
    let initialValue: String
    let onCommit: (String) -> Void

    @State private var draft: String?

    var body: some View {
        Group {
            if isSecure {
                SecureField(title, text: binding)
            } else {
                TextField(title, text: binding)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(commit)
        .onDisappear(perform: commit)
    }

    private var binding: Binding<String> {
        Binding(
            get: { draft ?? initialValue },
            set: { draft = $0 }
        )
    }

    private func commit() {
        guard let draft, draft != initialValue else { return }
        onCommit(draft)
    }
}
