import SwiftUI

/// 搜索页：接入插件后由插件的 searchComic 提供结果
struct SearchView: View {
    @State private var keyword = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "搜索漫画",
                systemImage: "magnifyingglass",
                description: Text("安装插件后即可搜索漫画")
            )
            .navigationTitle(AppTab.search.title)
            .searchable(text: $keyword, prompt: "搜索漫画")
        }
    }
}

#Preview {
    SearchView()
}
