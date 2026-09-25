import SwiftUI

/// 设置页：网络代理、简繁转换、插件管理、数据管理、关于
struct SettingsView: View {
    @AppStorage(SettingsKey.proxyEnabled) private var proxyEnabled = false
    @AppStorage(SettingsKey.proxyType) private var proxyType = ProxyType.http.rawValue
    @AppStorage(SettingsKey.proxyHost) private var proxyHost = ""
    @AppStorage(SettingsKey.proxyPort) private var proxyPort = ""
    @AppStorage(SettingsKey.chineseConversion) private var chineseConversion = ChineseConversion.off.rawValue
    @AppStorage(SettingsKey.readingDirection) private var readingDirection = ReadingDirection.vertical.rawValue
    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(SettingsKey.imageConcurrency) private var imageConcurrency = ImageSettings.defaultConcurrency
    @AppStorage(SettingsKey.imageTimeoutSeconds) private var imageTimeout = ImageSettings.defaultTimeoutSeconds

    @State private var pendingAction: DataAction?
    @State private var resultMessage: String?
    @State private var isTestingProxy = false
    @State private var proxyTestResult: ProxyTestResult?

    /// 代理测试结果弹窗的内容
    private struct ProxyTestResult: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// 需要二次确认的数据操作
    private enum DataAction: String, Identifiable {
        case clearImageCache = "清空图片缓存"
        case clearHistory = "清空浏览记录"

        var id: String { rawValue }
    }

    var body: some View {
        Form {
            pluginSection
            appearanceSection
            readingSection
            imageSection
            proxySection
            languageSection
            dataSection
            aboutSection
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            confirmationTitle,
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
        .alert(item: $proxyTestResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private var confirmationTitle: String {
        guard let pendingAction else { return "" }
        return "确定要\(pendingAction.rawValue)？"
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

    private var appearanceSection: some View {
        Section("外观") {
            Picker("主题", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
        }
    }

    private var readingSection: some View {
        Section {
            Picker("阅读方向", selection: $readingDirection) {
                ForEach(ReadingDirection.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
        } header: {
            Text("阅读")
        } footer: {
            Text("纵向连续适合长条漫画；左右翻页适合单页作品。")
        }
    }

    private var imageSection: some View {
        Section {
            Stepper(value: $imageConcurrency, in: 1...10) {
                LabeledContent("并发下载数", value: "\(imageConcurrency)")
            }

            Stepper(value: $imageTimeout, in: 5...120, step: 5) {
                LabeledContent("单张超时", value: "\(imageTimeout) 秒")
            }
        } header: {
            Text("图片")
        } footer: {
            Text("并发数越高加载越快，但图源限速时反而更容易超时；超时或失败会自动重试一次。")
        }
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

                Button {
                    Task { await testProxy() }
                } label: {
                    if isTestingProxy {
                        HStack {
                            ProgressView()
                            Text("正在测试")
                        }
                    } else {
                        Text("测试代理")
                    }
                }
                .disabled(isTestingProxy)
            }
        } header: {
            Text("网络代理")
        } footer: {
            Text("代理对所有插件发出的请求生效。改完配置点一次「测试代理」确认是否真的通。")
        }
    }

    private func testProxy() async {
        isTestingProxy = true
        let outcome = await ProxyTester.test(proxy: ProxyConfiguration.current())
        isTestingProxy = false

        proxyTestResult = ProxyTestResult(
            title: outcome.success ? "代理已生效" : "代理未生效",
            message: outcome.message
        )
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
