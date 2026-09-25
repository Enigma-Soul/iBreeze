import SwiftUI
import Observation

/// 详情页 VM：拉取漫画信息与章节列表
@MainActor
@Observable
final class ComicDetailViewModel {
    private(set) var detail: ComicDetailResult?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    let sourceID: String
    let comicID: String

    init(sourceID: String, comicID: String) {
        self.sourceID = sourceID
        self.comicID = comicID
    }

    var info: ComicDetailResult.ComicInfo? { detail?.data?.normal?.comicInfo }
    var chapters: [ChapterSummary] { detail?.data?.normal?.eps ?? [] }
    var recommended: [ComicListItem] { detail?.data?.normal?.recommend ?? [] }

    /// 插件给的标签，扁平化成一行文字
    var tags: [String] {
        (info?.metadata ?? []).flatMap { group in
            (group.value ?? []).compactMap(\.name).filter { !$0.isEmpty }
        }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let source = try await PluginRegistry.shared.source(for: sourceID)
            detail = try await source.comicDetail(comicID: comicID)
            errorMessage = nil
            recordHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 打开详情即记入浏览记录
    private func recordHistory() {
        guard let info else { return }
        ReadingHistoryStore.shared.record(ReadingHistoryEntry(
            source: sourceID,
            comicID: comicID,
            title: info.title ?? comicID,
            coverURL: info.cover?.url,
            chapterID: chapters.first?.id,
            chapterName: chapters.first?.name,
            updatedAt: Date()
        ))
    }
}

/// 详情页：封面信息区 → 操作栏 → 章节 → 标签 → 相关推荐
struct ComicDetailPage: View {
    let sourceID: String
    let comicID: String

    @State private var viewModel: ComicDetailViewModel
    private var favorites = FavoritesStore.shared
    private var history = ReadingHistoryStore.shared

    init(sourceID: String, comicID: String) {
        self.sourceID = sourceID
        self.comicID = comicID
        _viewModel = State(initialValue: ComicDetailViewModel(sourceID: sourceID, comicID: comicID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                Divider()
                actionBar
                Divider()
                chapterSection
                tagSection
                recommendSection
            }
        }
        .navigationTitle(viewModel.info?.title ?? "详情")
        .navigationBarTitleDisplayMode(.inline)
        .appNavigationDestinations()
        .task { if viewModel.detail == nil { await viewModel.load() } }
        .overlay { loadingOverlay }
    }

    // MARK: - 信息区

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 14) {
            PluginImageView(sourceID: sourceID, url: viewModel.info?.cover?.url)
                .frame(width: 120, height: 168)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.thumbnail, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text((viewModel.info?.title ?? "加载中…").convertedChinese)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                if let creator = viewModel.info?.creator?.name, !creator.isEmpty {
                    Text(creator.convertedChinese)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if let description = viewModel.info?.description, !description.isEmpty {
                    Text(description.convertedChinese)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(AppTheme.Spacing.page)
    }

    // MARK: - 操作栏

    private var actionBar: some View {
        HStack(spacing: 10) {
            if let route = readerRoute {
                NavigationLink(value: route) {
                    Label(continueChapter == nil ? "开始阅读" : "继续阅读", systemImage: "book")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Label("暂无章节", systemImage: "book")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            squareButton(
                systemImage: isFavorite ? "heart.fill" : "heart",
                tint: isFavorite ? .red : .accentColor,
                label: isFavorite ? "取消收藏" : "收藏"
            ) {
                favorites.toggle(FavoriteEntry(
                    source: sourceID,
                    comicID: comicID,
                    title: viewModel.info?.title ?? comicID,
                    coverURL: viewModel.info?.cover?.url,
                    addedAt: Date()
                ))
            }
        }
        .padding(.horizontal, AppTheme.Spacing.page)
        .padding(.vertical, 12)
    }

    private func squareButton(
        systemImage: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - 章节

    @ViewBuilder
    private var chapterSection: some View {
        if !viewModel.chapters.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("章节")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("共 \(viewModel.chapters.count) 章")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppTheme.Spacing.page)
                .padding(.vertical, 10)

                ForEach(viewModel.chapters) { chapter in
                    NavigationLink(value: AppRoute.reader(
                        sourceID: sourceID,
                        comicID: comicID,
                        chapterID: chapter.resolvedRequestId,
                        chapterName: chapter.name ?? "",
                        title: viewModel.info?.title ?? ""
                    )) {
                        HStack(spacing: 8) {
                            if isCurrentChapter(chapter) {
                                Text("续")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }

                            Text((chapter.name ?? chapter.id).convertedChinese)
                                .font(.subheadline)
                                .foregroundStyle(isCurrentChapter(chapter) ? Color.accentColor : Color.primary)
                                .lineLimit(1)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, AppTheme.Spacing.page)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, AppTheme.Spacing.page)
                }
            }
        }
    }

    // MARK: - 标签与推荐

    @ViewBuilder
    private var tagSection: some View {
        if !viewModel.tags.isEmpty {
            FlowLayout(spacing: 6) {
                ForEach(viewModel.tags, id: \.self) { tag in
                    TagChip(text: tag)
                }
            }
            .padding(AppTheme.Spacing.page)
        }
    }

    @ViewBuilder
    private var recommendSection: some View {
        if !viewModel.recommended.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("相关推荐")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, AppTheme.Spacing.page)

                ComicPosterRow(items: viewModel.recommended, sourceID: sourceID) { item in
                    AppRoute.comicDetail(sourceID: sourceID, comicID: item.id)
                }
            }
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if viewModel.detail == nil, !viewModel.isLoading {
            if let message = viewModel.errorMessage {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(message))
            }
        }
    }

    // MARK: - 辅助

    /// 浏览记录里读到的章节，用于「继续阅读」与章节高亮
    private var continueChapter: ChapterSummary? {
        guard let entry = history.entries.first(where: { $0.source == sourceID && $0.comicID == comicID }),
              let chapterID = entry.chapterID
        else { return nil }
        return viewModel.chapters.first { $0.resolvedRequestId == chapterID || $0.id == chapterID }
    }

    private var readingTarget: ChapterSummary? {
        continueChapter ?? viewModel.chapters.first
    }

    private var readerRoute: AppRoute? {
        guard let target = readingTarget else { return nil }
        return .reader(
            sourceID: sourceID,
            comicID: comicID,
            chapterID: target.resolvedRequestId,
            chapterName: target.name ?? "",
            title: viewModel.info?.title ?? ""
        )
    }

    private func isCurrentChapter(_ chapter: ChapterSummary) -> Bool {
        continueChapter?.id == chapter.id
    }

    private var isFavorite: Bool {
        favorites.contains(source: sourceID, comicID: comicID)
    }
}
