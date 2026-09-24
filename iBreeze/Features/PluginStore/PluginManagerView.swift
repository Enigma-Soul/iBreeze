import SwiftUI
import Observation

/// 插件管理 VM：云端列表、安装、更新、卸载
@MainActor
@Observable
final class PluginManagerViewModel {
    private(set) var cloudPlugins: [RemotePlugin] = []
    private(set) var isLoadingCloud = false
    private(set) var busyPluginID: String?
    private(set) var errorMessage: String?
    var bundleURLText = ""

    var installed: [InstalledPlugin] { PluginRegistry.shared.installed }

    func loadCloudPlugins() async {
        guard !isLoadingCloud, cloudPlugins.isEmpty else { return }
        isLoadingCloud = true
        defer { isLoadingCloud = false }

        do {
            cloudPlugins = try await PluginRegistry.shared.cloudPlugins()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func install(_ remote: RemotePlugin) async {
        await perform(id: remote.id) {
            try await PluginRegistry.shared.install(remote)
        }
    }

    func installFromURL() async {
        let text = bundleURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), !text.isEmpty else {
            errorMessage = "请填写有效的 bundle 地址"
            return
        }

        await perform(id: text) {
            try await PluginRegistry.shared.install(bundleURL: url)
        }
        bundleURLText = ""
    }

    func update(_ plugin: InstalledPlugin) async {
        await perform(id: plugin.uuid) {
            let updated = try await PluginRegistry.shared.update(plugin)
            if !updated { self.errorMessage = "\(plugin.name) 已是最新版本" }
        }
    }

    func uninstall(_ plugin: InstalledPlugin) async {
        await perform(id: plugin.uuid) {
            try await PluginRegistry.shared.uninstall(plugin)
        }
    }

    func isInstalled(_ remote: RemotePlugin) -> Bool {
        installed.contains { $0.uuid == remote.manifest.uuid }
    }

    /// 统一处理忙状态与错误
    private func perform(id: String, _ action: @escaping () async throws -> Void) async {
        busyPluginID = id
        errorMessage = nil
        defer { busyPluginID = nil }

        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 插件管理：已安装列表、云端安装、网络安装
struct PluginManagerView: View {
    @State private var viewModel = PluginManagerViewModel()
    @State private var pendingRemoval: InstalledPlugin?

    var body: some View {
        List {
            installedSection
            cloudSection
            networkSection

            if let message = viewModel.errorMessage {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("插件管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadCloudPlugins() }
        .confirmationDialog(
            "确定卸载「\(pendingRemoval?.name ?? "")」？",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("卸载", role: .destructive) {
                guard let plugin = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await viewModel.uninstall(plugin) }
            }
        }
    }

    @ViewBuilder
    private var installedSection: some View {
        Section("已安装") {
            if viewModel.installed.isEmpty {
                Text("还没有安装插件")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.installed) { plugin in
                    row(for: plugin)
                }
            }
        }
    }

    private func row(for plugin: InstalledPlugin) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                PluginSettingsView(plugin: plugin)
            } label: {
                HStack(spacing: 12) {
                    PluginIconImage(url: plugin.iconURL)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(plugin.name)
                        Text(plugin.version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if viewModel.busyPluginID == plugin.uuid {
                ProgressView()
            } else {
                Button("更新") {
                    Task { await viewModel.update(plugin) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .swipeActions {
            Button("卸载", role: .destructive) { pendingRemoval = plugin }
        }
    }

    private var cloudSection: some View {
        Section("在线安装") {
            if viewModel.isLoadingCloud {
                HStack {
                    ProgressView()
                    Text("正在获取插件列表")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.cloudPlugins.isEmpty {
                Text("插件列表获取失败，可稍后重试或改用网络安装")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.cloudPlugins) { remote in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(remote.manifest.name)
                            Text(remote.manifest.describe ?? remote.repo)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if viewModel.busyPluginID == remote.id {
                            ProgressView()
                        } else if viewModel.isInstalled(remote) {
                            Text("已安装")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("安装") {
                                Task { await viewModel.install(remote) }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var networkSection: some View {
        Section {
            TextField("bundle 地址（.cjs / .bundle.cjs）", text: $viewModel.bundleURLText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            Button("从网络安装") {
                Task { await viewModel.installFromURL() }
            }
            .disabled(viewModel.bundleURLText.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("网络安装")
        } footer: {
            Text("直接填写插件 bundle 的下载地址，安装时会校验插件 uuid。")
        }
    }
}
