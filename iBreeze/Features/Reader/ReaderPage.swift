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

    /// 预取当前位置往后三页，减少翻页时的白屏
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

/// 阅读页：三段点击区 + 玻璃工具栏 + 页码网格跳转。
///
/// 点击区域按 EhViewer 的做法划分：左右各 30% 翻页、中间 40% 切换工具栏，
/// 上下各留 20% 死区，避免点顶部/底部误翻页。
struct ReaderPage: View {
    let sourceID: String
    let chapterName: String
    let comicTitle: String

    @State private var viewModel: ReaderViewModel
    /// 当前页（双向绑定给 scrollPosition）
    @State private var currentPageID: String?
    @State private var showsChrome = true
    @State private var showsPageGrid = false
    @State private var showsSettings = false
    /// 拖滑杆时只写本地状态，松手才提交，避免每动一像素就让整页重算
    @State private var draggingPage: Double?

    @AppStorage(SettingsKey.readingDirection) private var directionRaw = ReadingDirection.vertical.rawValue
    @Environment(\.dismiss) private var dismiss

    private var direction: ReadingDirection {
        ReadingDirection(rawValue: directionRaw) ?? .vertical
    }

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
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if direction.isPaged {
                    pagedReader
                } else {
                    continuousReader
                }

                chrome
            }
            // 用 simultaneousGesture 而不是覆盖一层按钮：后者会把滚动一起吃掉
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    handleTap(at: value.location, size: geometry.size)
                }
            )
        }
        .background(Color.black)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .statusBarHidden(!showsChrome)
        .task { if viewModel.pages.isEmpty { await viewModel.load() } }
        .onChange(of: currentPageID) { _, _ in
            viewModel.prefetch(around: currentPageNumber - 1)
        }
        .sheet(isPresented: $showsPageGrid) {
            PageGridSheet(
                pages: viewModel.pages,
                currentIndex: currentPageNumber - 1,
                onSelect: { goTo(index: $0) }
            )
        }
        .sheet(isPresented: $showsSettings) {
            ReaderSettingsSheet()
        }
        .overlay { stateOverlay }
    }

    // MARK: - 两种翻页

    private var continuousReader: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.pages) { page in
                    PluginImageView(sourceID: sourceID, url: page.url, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .id(page.id)
                }
            }
        }
        .scrollPosition(id: $currentPageID)
        .ignoresSafeArea()
    }

    private var pagedReader: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(viewModel.pages) { page in
                    PluginImageView(sourceID: sourceID, url: page.url, contentMode: .fit)
                        .containerRelativeFrame(.horizontal)
                        .id(page.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentPageID)
        // 只影响这一层：工具栏是兄弟视图，不会被翻转
        .environment(\.layoutDirection, direction == .rightToLeft ? .rightToLeft : .leftToRight)
        .ignoresSafeArea()
    }

    // MARK: - 工具栏

    @ViewBuilder
    private var chrome: some View {
        if showsChrome, !viewModel.pages.isEmpty {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottomBar
            }
            .transition(.opacity)
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            glassCapsule {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("返回")

                Text(chapterName.isEmpty ? comicTitle : chapterName)
                    .font(.footnote)
                    .lineLimit(1)
                    .padding(.trailing, 4)
            }

            Spacer(minLength: 0)

            glassCapsule {
                Button { showsPageGrid = true } label: {
                    Image(systemName: "square.grid.3x3")
                }
                .accessibilityLabel("目录")

                Button { showsSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("阅读设置")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Text("\(currentPageNumber)")
                    .font(.caption.monospacedDigit())

                Slider(
                    value: Binding(
                        get: { draggingPage ?? Double(currentPageNumber) },
                        set: { draggingPage = $0 }
                    ),
                    in: 1...Double(max(viewModel.pages.count, 1)),
                    step: 1,
                    onEditingChanged: { editing in
                        guard !editing, let target = draggingPage else { return }
                        draggingPage = nil
                        goTo(index: Int(target) - 1)
                    }
                )
                .tint(.white)

                Text("\(viewModel.pages.count)")
                    .font(.caption.monospacedDigit())
            }

            chapterSwitcher
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // 阅读器底色恒为黑，工具栏不跟随明暗模式，否则浅色模式下会刺眼
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var chapterSwitcher: some View {
        HStack {
            Button {
                guard let previous = viewModel.previousChapter else { return }
                Task { await viewModel.switchTo(chapter: previous) }
            } label: {
                Label("上一章", systemImage: "chevron.left")
                    .font(.caption)
            }
            .disabled(viewModel.previousChapter == nil)

            Spacer()

            Text(chapterName.isEmpty ? comicTitle : chapterName)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            Spacer()

            Button {
                guard let next = viewModel.nextChapter else { return }
                Task { await viewModel.switchTo(chapter: next) }
            } label: {
                Label("下一章", systemImage: "chevron.right")
                    .font(.caption)
            }
            .disabled(viewModel.nextChapter == nil)
        }
    }

    private func glassCapsule<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Color.black.opacity(0.45), in: Capsule())
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
    }

    // MARK: - 交互

    private var currentPageNumber: Int {
        guard let currentPageID,
              let index = viewModel.pages.firstIndex(where: { $0.id == currentPageID })
        else { return 1 }
        return index + 1
    }

    private func handleTap(at location: CGPoint, size: CGSize) {
        // 上下各 20% 是死区
        guard location.y > size.height * 0.2, location.y < size.height * 0.8 else { return }

        let ratio = location.x / max(size.width, 1)
        let tapsBackward = direction == .rightToLeft ? ratio > 0.7 : ratio < 0.3
        let tapsForward = direction == .rightToLeft ? ratio < 0.3 : ratio > 0.7

        if tapsBackward {
            goTo(index: currentPageNumber - 2)
        } else if tapsForward {
            goTo(index: currentPageNumber)
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { showsChrome.toggle() }
        }
    }

    private func goTo(index: Int) {
        guard viewModel.pages.indices.contains(index) else { return }
        withAnimation(.snappy(duration: 0.25)) {
            currentPageID = viewModel.pages[index].id
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if viewModel.pages.isEmpty {
            if let message = viewModel.errorMessage {
                ContentUnavailableView(
                    "无法打开章节",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            } else {
                ProgressView().tint(.white)
            }
        }
    }
}
