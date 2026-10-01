import SwiftUI

/// 插件登录表单：字段完全由插件声明的 scheme 驱动，宿主不写死账号密码
struct PluginLoginSheet: View {
    let pluginName: String

    @State private var viewModel: PluginLoginViewModel

    /// 关闭一律走中心：它才是 `.sheet(item:)` 的绑定，直接 dismiss 会留下脏状态，
    /// 同一个插件再报未授权就弹不出来了
    private func close() {
        PluginLoginCenter.shared.dismiss()
    }

    init(pluginID: String, pluginName: String, notice: String? = nil) {
        self.pluginName = pluginName
        _viewModel = State(initialValue: PluginLoginViewModel(pluginID: pluginID, notice: notice))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let notice = viewModel.notice {
                    Section {
                        Text(notice.convertedChinese)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(viewModel.fields) { field in
                        PluginFormField(
                            label: field.label.convertedChinese,
                            isSecure: field.isSecure,
                            value: field.value
                        ) { viewModel.update(key: field.key, value: $0) }
                    }
                } footer: {
                    if let error = viewModel.errorMessage {
                        Text(error.convertedChinese)
                    } else {
                        Text("账号密码保存在插件自己的配置里，登录成功后由插件带在后续请求上。")
                    }
                }
            }
            .navigationTitle(viewModel.title.convertedChinese)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { close() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            if await viewModel.submit() { close() }
                        }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Text(viewModel.submitText.convertedChinese)
                        }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
            .overlay {
                if viewModel.isLoading { ProgressView() }
            }
        }
        .task { await viewModel.load() }
        // 下滑关掉时绑定还是非空，同一插件再报未授权就弹不出来了
        .onDisappear(perform: close)
    }
}
