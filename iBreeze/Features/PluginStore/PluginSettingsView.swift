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
    private let plugin: InstalledPlugin

    init(plugin: InstalledPlugin) {
        self.plugin = plugin
        _viewModel = State(initialValue: PluginSettingsViewModel(plugin: plugin))
    }

    var body: some View {
        Form {
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
