import SwiftUI

/// 收藏页：本地收藏 + 插件云端收藏
struct FavoritesView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "暂无收藏",
                systemImage: "heart",
                description: Text("收藏的漫画会显示在这里")
            )
            .navigationTitle(AppTab.favorites.title)
        }
    }
}

#Preview {
    FavoritesView()
}
