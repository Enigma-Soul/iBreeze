import SwiftUI

/// 首页：顶部切换插件源与入口，下面是该入口的内容。
///
/// 与 EhViewer 一样，首页/搜索/收藏共用同一套列表容器，首页只负责选数据源：
/// 源 = 已安装插件，入口 = 插件声明的「最新 / 热门 / 排行 / 导航」等。
struct HomeView: View {
    @Environment(PluginRegistry.self) private var registry
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sourceBar
                content
            }
            .navigationTitle(AppTab.home.title)
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationDestinations()
            .toolbar { toolbarContent }
        }
        .task { await viewModel.reload() }
        .onChange(of: registry.installed.map(\.uuid)) { _, _ in
            Task { await viewModel.reload() }
        }
    }

    // MARK: - 顶部

    @ViewBuilder
    private var sourceBar: some View {
        if !viewModel.sources.isEmpty {
            VStack(spacing: 10) {
                searchField

                SourceTabStrip(sources: viewModel.sources, selection: Binding(
                    get: { viewModel.selectedSourceID },
                    set: { newValue in
                        guard let newValue else { return }
                        Task { await viewModel.select(sourceID: newValue) }
                    }
                ))

                if viewModel.entries.count > 1 {
                    EntryPillStrip(entries: viewModel.entries, selection: Binding(
                        get: { viewModel.selectedEntryID },
                        set: { newValue in
                            guard let newValue else { return }
                            Task { await viewModel.select(entryID: newValue) }
                        }
                    ))
                }

                Divider()
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    /// 顶部搜索框：直接在当前源里搜（不少插件只有搜索入口）
    @ViewBuilder
    private var searchField: some View {
        if let source = viewModel.selectedSource {
            NavigationLink {
                PluginSearchPage(sourceID: source.uuid, sourceName: source.name, initialKeyword: "")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("在 \(source.name) 中搜索")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                .padding(.horizontal, AppTheme.Spacing.page)
            }
            .buttonStyle(.plain)
        }
    }

    /// 当前列表带筛选器时（排行榜之类）才显示筛选入口
    private var activeFilterList: ComicListViewModel? {
        guard case .list(let list) = viewModel.content, list.hasFilter else { return nil }
        return list
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let list = activeFilterList {
            ToolbarItem(placement: .topBarTrailing) {
                FilterMenu(
                    title: list.filterTitle,
                    options: list.filterOptions,
                    activeLabel: list.activeFilterLabel
                ) { option in
                    Task { await list.apply(option: option) }
                }
            }
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if viewModel.sources.isEmpty {
            ContentUnavailableView(
                "还没有安装插件",
                systemImage: "puzzlepiece.extension",
                description: Text("去「设置 → 插件管理」安装后即可浏览")
            )
        } else if let source = viewModel.selectedSource, viewModel.selectedSourceNeedsSearch {
            ContentUnavailableView {
                Label("只能搜索", systemImage: "magnifyingglass")
            } description: {
                Text("\(source.name) 没有提供浏览入口")
            } actions: {
                NavigationLink("搜索该插件") {
                    PluginSearchPage(sourceID: source.uuid, sourceName: source.name, initialKeyword: "")
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            entryContent
        }
    }

    @ViewBuilder
    private var entryContent: some View {
        switch viewModel.content {
        case .list(let list):
            ComicResultList(
                items: list.items,
                sourceID: viewModel.selectedSourceID ?? "",
                isLoading: list.isLoading,
                hasReachedMax: list.hasReachedMax,
                loadMore: { Task { await list.loadMore() } },
                header: { ContinueReadingStrip() }
            )

        case .route(let title, let route):
            VStack(spacing: 12) {
                NavigationLink(title, value: route)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .unsupported(let reason):
            ContentUnavailableView("暂不支持", systemImage: "questionmark.circle", description: Text(reason))

        case nil:
            ProgressView()
        }
    }
}
