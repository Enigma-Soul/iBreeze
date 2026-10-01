import SwiftUI

/// 插件表单里的一个文本项（登录表单用），密码类走 SecureField
struct PluginFormField: View {
    let label: String
    var isSecure = false
    let value: String
    let onChange: (String) -> Void

    var body: some View {
        field
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(isSecure ? .password : .username)
    }

    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(label, text: binding)
        } else {
            TextField(label, text: binding)
        }
    }

    /// 值由 view model 持有，这里只做转发，避免两份状态不同步
    private var binding: Binding<String> {
        Binding(get: { value }, set: onChange)
    }
}
