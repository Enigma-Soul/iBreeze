import SwiftUI

/// 插件图片：图片字节由插件下载，这里只负责走缓存与占位
struct PluginImageView: View {
    let sourceID: String
    let url: String?
    var contentMode: ContentMode = .fill

    @Environment(PluginRegistry.self) private var registry
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: url) { await load() }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(uiColor: .tertiarySystemFill))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
    }

    private func load() async {
        guard let url, !url.isEmpty else { return }
        image = nil

        guard let source = try? await registry.source(for: sourceID) else { return }
        image = await ComicImageLoader.shared.image(pluginUUID: sourceID, url: url, source: source)
    }
}
