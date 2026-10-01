import SwiftUI

/// 插件图标图片：首页入口、已安装列表共用同一套占位逻辑。
///
/// 插件图标是普通的 https 地址，不需要经过插件下载，因此这里用 `AsyncImage`。
struct PluginIconImage: View {
    let url: String?

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Image(systemName: "puzzlepiece.extension")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}
