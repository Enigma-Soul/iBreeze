import SwiftUI
import Observation

/// 阅读页 VM：拉取章节图片，支持前后章切换
@MainActor
@Observable
final class ReaderViewModel {
    private(set) var pages: [ChapterPage] = []
    private(set) var chapters: [ChapterSummary] = []
    private(set) var chapterID: String
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    let sourceID: String
    let comicID: String

    init(sourceID: String, comicID: String, chapterID: String) {
        self.sourceID = sourceID
        self.comicID = comicID
        self.chapterID = chapterID
    }

    var chapterIndex: Int? {
        chapters.firstIndex { $0.resolvedRequestId == chapterID || $0.id == chapterID }
    }

    var previousChapter: ChapterSummary? {
        guard let index = chapterIndex, index > 0 else { return nil }
        return chapters[index - 1]
    }

    var nextChapter: ChapterSummary? {
        guard let index = chapterIndex, index + 1 < chapters.count else { return nil }
        return chapters[index + 1]
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let source = try await PluginRegistry.shared.source(for: sourceID)
            let snapshot = try await source.readSnapshot(comicID: comicID, chapterID: chapterID)

            pages = snapshot.data?.chapter?.pages ?? []
            chapters = snapshot.data?.chapters ?? []
            errorMessage = pages.isEmpty ? "该章节没有返回图片" : nil
            prefetch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 切换章节并重新拉取
    func switchTo(chapter: ChapterSummary) async {
        chapterID = chapter.resolvedRequestId
        pages = []
        await load()
    }

    /// 预取前几页，减少滚动时的白屏
    private func prefetch() {
        let urls = pages.prefix(3).compactMap(\.url)
        guard !urls.isEmpty, let source = try? PluginRegistry.shared.cachedSource(for: sourceID) else { return }
        Task { await ComicImageLoader.shared.prefetch(pluginUUID: sourceID, urls: urls, source: source) }
    }
}

/// 阅读页：整章纵向连读
struct ReaderPage: View {
    let sourceID: String
    let comicID: String
    let chapterName: String
    let comicTitle: String

    @State private var viewModel: ReaderViewModel

    init(sourceID: String, comicID: String, chapterID: String, chapterName: String, comicTitle: String) {
        self.sourceID = sourceID
        self.comicID = comicID
        self.chapterName = chapterName
        self.comicTitle = comicTitle
        _viewModel = State(initialValue: ReaderViewModel(
            sourceID: sourceID,
            comicID: comicID,
            chapterID: chapterID
        ))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.pages) { page in
                    PluginImageView(sourceID: sourceID, url: page.url, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(chapterName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { chapterToolbar }
        .task { if viewModel.pages.isEmpty { await viewModel.load() } }
        .overlay { emptyOverlay }
        .sensoryFeedback(.success, trigger: viewModel.chapterID)
    }

    @ToolbarContentBuilder
    private var chapterToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                guard let previous = viewModel.previousChapter else { return }
                Task { await viewModel.switchTo(chapter: previous) }
            } label: {
                Label("上一章", systemImage: "chevron.left")
            }
            .disabled(viewModel.previousChapter == nil)

            Spacer()

            Button {
                guard let next = viewModel.nextChapter else { return }
                Task { await viewModel.switchTo(chapter: next) }
            } label: {
                Label("下一章", systemImage: "chevron.right")
            }
            .disabled(viewModel.nextChapter == nil)
        }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if viewModel.pages.isEmpty {
            if let message = viewModel.errorMessage {
                ContentUnavailableView("无法打开章节", systemImage: "exclamationmark.triangle", description: Text(message))
            } else {
                ProgressView()
            }
        }
    }
}
