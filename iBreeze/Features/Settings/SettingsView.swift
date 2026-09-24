import SwiftUI

/// 设置页：网络代理、简繁转换、插件管理、数据管理、关于
struct SettingsView: View {
    @AppStorage(SettingsKey.proxyEnabled) private var proxyEnabled = false
    @AppStorage(SettingsKey.proxyType) private var proxyType = ProxyType.http.rawValue
    @AppStorage(SettingsKey.proxyHost) private var proxyHost = ""
    @AppStorage(SettingsKey.proxyPort) private var proxyPort = ""
    @AppStorage(SettingsKey.chineseConversion) private var chineseConversion = ChineseConversion.off.rawValue

    @State private var pendingAction: DataAction?
    @State private var resultMessage: String?

    /// 需要二次确认的数据操作
    private enum DataAction: String, Identifiable {
        case clearImageCache = "清空图片缓存"
        case clearHistory = "清空浏览记录"

        var id: String { rawValue }
    }

    var body: some View {
        Form {
            proxySection
            languageSection
            pluginSection
            dataSection
            aboutSection
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            pendingAction.map { "确定要\($0.rawValue)？" } ?? "",
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible
        ) {
            Button("确定", role: .destructive) {
                guard let action = pendingAction else { return }
                pendingAction = nil
                Task { await perform(action) }
            }
        }
        .alert("完成", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private var dataSection: some View {
        Section("数据") {
            Button(DataAction.clearImageCache.rawValue) { pendingAction = .clearImageCache }
            Button(DataAction.clearHistory.rawValue) { pendingAction = .clearHistory }
        }
    }

    private func perform(_ action: DataAction) async {
        switch action {
        case .clearImageCache:
            await ComicImageLoader.shared.clear()
        case .clearHistory:
            ReadingHistoryStore.shared.clear()
        }
        resultMessage = "已\(action.rawValue)"
    }

    private var proxySection: some View {
        Section {
            Toggle("启用代理", isOn: $proxyEnabled)

            if proxyEnabled {
                Picker("类型", selection: $proxyType) {
                    ForEach(ProxyType.allCases) { type in
                        Text(type.title).tag(type.rawValue)
                    }
                }

                TextField("服务器", text: $proxyHost)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("端口", text: $proxyPort)
                    .keyboardType(.numberPad)
            }
        } header: {
            Text("网络代理")
        } footer: {
            Text("代理对所有插件发出的请求生效。")
        }
    }

    private var languageSection: some View {
        Section {
            Picker("简繁转换", selection: $chineseConversion) {
                ForEach(ChineseConversion.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
        } header: {
            Text("语言")
        } footer: {
            Text("按 OpenCC 规则转换插件返回的标题与正文用字。")
        }
    }

    private var pluginSection: some View {
        Section("插件") {
            NavigationLink {
                PluginManagerView()
            } label: {
                Label("插件管理", systemImage: "puzzlepiece.extension")
            }
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: Self.appVersion)
            LabeledContent("插件内核", value: "Breeze")
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
