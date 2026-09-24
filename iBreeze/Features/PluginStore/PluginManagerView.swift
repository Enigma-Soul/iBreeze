import SwiftUI

/// 插件管理：安装、更新、卸载
struct PluginManagerView: View {
    var body: some View {
        ContentUnavailableView(
            "插件管理",
            systemImage: "puzzlepiece.extension",
            description: Text("插件的安装与管理将在后续版本提供")
        )
        .navigationTitle("插件管理")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PluginManagerView()
    }
}
