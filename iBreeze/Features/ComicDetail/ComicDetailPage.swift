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

/// 详情页：封面、简介、章节列表
struct ComicDetailPage: View {
    let sourceID: String
    let comicID: String

    @State private var viewModel: ComicDetailViewModel
    private var favorites = FavoritesStore.shared

    init(sourceID: String, comicID: String) {
        self.sourceID = sourceID
        self.comicID = comicID
        _viewModel = State(initialValue: ComicDetailViewModel(sourceID: sourceID, comicID: comicID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                header
                chapterSection
                recommendSection
            }
            .padding(.vertical, AppTheme.Spacing.section)
        }
        .navigationTitle(viewModel.info?.title ?? "详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { favoriteButton }
        .task { if viewModel.detail == nil { await viewModel.load() } }
        .overlay { loadingOverlay }
    }

    @ToolbarContentBuilder
    private var favoriteButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                favorites.toggle(FavoriteEntry(
                    source: sourceID,
                    comicID: comicID,
                    title: viewModel.info?.title ?? comicID,
                    coverURL: viewModel.info?.cover?.url,
                    addedAt: Date()
                ))
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(isFavorite ? .pink : .primary)
            }
            .disabled(viewModel.info == nil)
            .accessibilityLabel(isFavorite ? "取消收藏" : "收藏")
        }
    }

    private var isFavorite: Bool {
        favorites.contains(source: sourceID, comicID: comicID)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            PluginImageView(sourceID: sourceID, url: viewModel.info?.cover?.url)
                .frame(width: 120, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.info?.title ?? "加载中…")
                    .font(.headline)

                if let creator = viewModel.info?.creator?.name, !creator.isEmpty {
                    Text(creator)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let description = viewModel.info?.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.Spacing.page)
        .padding(.top, AppTheme.Spacing.section)
        .padding(.bottom, AppTheme.Spacing.section)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .padding(.horizontal, AppTheme.Spacing.page)
    }

    @ViewBuilder
    private var chapterSection: some View {
        if !viewModel.chapters.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "章节")

                ForEach(viewModel.chapters) { chapter in
                    NavigationLink(value: AppRoute.reader(
                        sourceID: sourceID,
                        comicID: comicID,
                        chapterID: chapter.resolvedRequestId,
                        chapterName: chapter.name ?? "第 \(chapter.order ?? 0) 话",
                        title: viewModel.info?.title ?? ""
                    )) {
                        HStack {
                            Text(chapter.name ?? chapter.id)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, AppTheme.Spacing.page)
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, AppTheme.Spacing.page)
                }
            }
        }
    }

    @ViewBuilder
    private var recommendSection: some View {
        if !viewModel.recommended.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "相关推荐")
                ComicPosterRow(items: viewModel.recommended, sourceID: sourceID) { item in
                    AppRoute.comicDetail(sourceID: sourceID, comicID: item.id)
                }
            }
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if viewModel.detail == nil {
            if let message = viewModel.errorMessage {
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(message))
            } else {
                ProgressView()
            }
        }
    }
}
