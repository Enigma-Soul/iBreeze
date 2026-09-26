import SwiftUI

/// 插件图片：图片字节由插件下载，这里只负责走缓存、占位与重试
struct PluginImageView: View {
    let sourceID: String
    let url: String?
    var contentMode: ContentMode = .fill
    /// 阅读页传入页码：加载中显示序号，长条漫画也便于定位
    var pageNumber: Int?
    /// 占位高度：加载完成前先占住位置，避免列表跳动与重叠
    var placeholderHeight: CGFloat?
    /// 页面带来的透传上下文，可能含真实图址，必须回传给插件
    var extern: JSONValue?
    /// 所属章节：禁漫的图要靠章节 id 才能还原
    var chapterID: String?

    @Environment(PluginRegistry.self) private var registry
    @State private var image: UIImage?
    @State private var errorMessage: String?

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: image == nil ? placeholderHeight : nil)
            .task(id: url) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(Color(uiColor: .tertiarySystemFill))

            if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(errorMessage)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Button("重试") { Task { await load(force: true) } }
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
                .foregroundStyle(.secondary)
                .padding(12)
            } else if let pageNumber {
                Text("\(pageNumber)")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
    }

    private func load(force: Bool = false) async {
        guard let url, !url.isEmpty else { return }
        if force { image = nil }
        guard image == nil else { return }

        errorMessage = nil
        guard let source = try? await registry.source(for: sourceID) else {
            errorMessage = "插件未就绪"
            return
        }

        switch await ComicImageLoader.shared.load(
            pluginUUID: sourceID,
            url: url,
            extern: extern,
            chapterID: chapterID,
            source: source
        ) {
        case .success(let loaded):
            image = loaded
        case .failure(let message):
            errorMessage = message
        }
    }
}
