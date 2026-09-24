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
            prefetch(around: 0)
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

    /// 预取当前位置往后三页，减少滚动时的白屏
    func prefetch(around index: Int) {
        guard let source = try? PluginRegistry.shared.cachedSource(for: sourceID) else { return }

        let start = max(0, index)
        let end = min(pages.count, index + 4)
        guard start < end else { return }

        let urls = pages[start..<end].compactMap(\.url)
        guard !urls.isEmpty else { return }
        Task { await ComicImageLoader.shared.prefetch(pluginUUID: sourceID, urls: urls, source: source) }
    }
}

/// 阅读页：整章纵向连读
struct ReaderPage: View {
    let sourceID: String
    let chapterName: String
    let comicTitle: String

    @State private var viewModel: ReaderViewModel
    /// 当前停在的页，用于页码显示与预取
    @State private var currentPageID: String?
    /// 点击画面可隐藏顶栏与章节条，进入沉浸阅读
    @State private var showsChrome = true

    init(sourceID: String, comicID: String, chapterID: String, chapterName: String, comicTitle: String) {
        self.sourceID = sourceID
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
                        .id(page.id)
                }
            }
        }
        .scrollPosition(id: $currentPageID)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { showsChrome.toggle() }
        }
        .navigationTitle(chapterName.convertedChinese)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(showsChrome ? .visible : .hidden, for: .navigationBar)
        .task { if viewModel.pages.isEmpty { await viewModel.load() } }
        .onChange(of: currentPageID) { _, _ in viewModel.prefetch(around: currentPageNumber - 1) }
        .overlay(alignment: .bottom) { chapterBar }
        .overlay { emptyOverlay }
        .sensoryFeedback(.success, trigger: viewModel.chapterID)
    }

    /// 悬浮章节切换条：液态玻璃质感，压在内容之上
    @ViewBuilder
    private var chapterBar: some View {
        if showsChrome, !viewModel.pages.isEmpty {
            HStack(spacing: 16) {
                chapterButton(title: "上一章", systemImage: "chevron.left", chapter: viewModel.previousChapter)

                VStack(spacing: 2) {
                    Text((chapterName.isEmpty ? comicTitle : chapterName).convertedChinese)
                        .font(.footnote)
                        .lineLimit(1)
                    Text("\(currentPageNumber) / \(viewModel.pages.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 170)

                chapterButton(title: "下一章", systemImage: "chevron.right", chapter: viewModel.nextChapter)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassSurface(in: Capsule())
            .padding(.bottom, 12)
        }
    }

    /// 当前页序号，从 1 起
    private var currentPageNumber: Int {
        guard let currentPageID,
              let index = viewModel.pages.firstIndex(where: { $0.id == currentPageID })
        else { return 1 }
        return index + 1
    }

    private func chapterButton(title: String, systemImage: String, chapter: ChapterSummary?) -> some View {
        Button {
            guard let chapter else { return }
            Task { await viewModel.switchTo(chapter: chapter) }
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
        }
        .disabled(chapter == nil)
        .accessibilityLabel(title)
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
