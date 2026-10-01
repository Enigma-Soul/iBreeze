import SwiftUI
import Observation

/// 插件自定义页面 VM
@MainActor
@Observable
final class FunctionPageViewModel {
    private(set) var page: FunctionPage?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    let sourceID: String
    /// 插件入口上的标题，内嵌渲染时用作小节标题
    let title: String
    private let pageID: String

    init(sourceID: String, pageID: String, title: String = "") {
        self.sourceID = sourceID
        self.pageID = pageID
        self.title = title
    }

    func load() async {
        guard !isLoading, page == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let source = try await PluginRegistry.shared.source(for: sourceID)
            page = try await source.functionPage(id: pageID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 插件自定义页面的内容。
///
/// 拆成独立视图是为了让首页能直接内嵌渲染（禁漫的「推荐」这类入口），
/// 而不是先跳一个空页再加载。
struct FunctionPageContent: View {
    let sourceID: String
    let page: FunctionPage

    @Environment(PluginRegistry.self) private var registry

    var body: some View {
        if let body = page.scheme?.body {
            node(body, in: page)
                .padding(.vertical, 12)
        }
    }

    /// 递归渲染：返回值可能是任意组合，用 AnyView 才能自引用
    private func node(_ body: FunctionPage.BodyNode, in page: FunctionPage) -> AnyView {
        switch body {
        case .list(let children):
            return AnyView(VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    node(child, in: page)
                }
            })

        case .chipList(let key):
            return AnyView(chipList(page.chips(for: key)))

        case .actionGrid(let key):
            return AnyView(actionGrid(page.actionGrid(for: key)))

        case .comicGrid(let key, let sectionTitle):
            return AnyView(comicGrid(title: sectionTitle, items: page.comics(for: key)))

        case .comicSectionList(let key):
            return AnyView(VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(page.sections(for: key).enumerated()), id: \.offset) { _, section in
                    comicGrid(title: section.title, items: section.items ?? [])
                }
            })

        case .unknown:
            return AnyView(EmptyView())
        }
    }

    // MARK: - 各种内容形态

    @ViewBuilder
    private func chipList(_ items: [FunctionPage.ChipItem]) -> some View {
        if !items.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    if let route = route(for: item.action) {
                        NavigationLink(value: route) {
                            chipLabel(item.label)
                        }
                        .buttonStyle(.plain)
                    } else {
                        chipLabel(item.label)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.page)
        }
    }

    private func chipLabel(_ text: String) -> some View {
        Text(text.convertedChinese)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }

    @ViewBuilder
    private func actionGrid(_ items: [FunctionPage.GridItem]) -> some View {
        if !items.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: AppTheme.Spacing.grid)], spacing: AppTheme.Spacing.grid) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    if let route = route(for: PluginActionRouter.action(from: item.action)) {
                        NavigationLink(value: route) {
                            gridCard(item)
                        }
                        .buttonStyle(.plain)
                    } else {
                        gridCard(item)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.page)
        }
    }

    private func gridCard(_ item: FunctionPage.GridItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PluginImageView(sourceID: sourceID, url: item.cover?.url, extern: item.cover?.extern)
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.thumbnail, style: .continuous))

            Text((item.title ?? "").convertedChinese)
                .font(.subheadline)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func comicGrid(title: String?, items: [ComicListItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let title, !title.isEmpty {
                    Text(title.convertedChinese)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, AppTheme.Spacing.page)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.grid) {
                        ForEach(items) { item in
                            NavigationLink(value: AppRoute.comicDetail(sourceID: sourceID, comicID: item.id)) {
                                ComicCoverCard(item: item, sourceID: sourceID, width: 110)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.page)
                }
            }
        }
    }

    private func route(for action: PluginAction?) -> AppRoute? {
        guard let action else { return nil }
        let name = registry.plugin(uuid: sourceID)?.name ?? ""
        return PluginActionRouter.route(for: action, sourceID: sourceID, sourceName: name)
    }
}

/// 插件自定义页面（推入式，独立成页时用）
struct FunctionPageView: View {
    let sourceID: String
    let pageID: String
    let title: String

    @State private var viewModel: FunctionPageViewModel

    init(sourceID: String, pageID: String, title: String) {
        self.sourceID = sourceID
        self.pageID = pageID
        self.title = title
        _viewModel = State(initialValue: FunctionPageViewModel(sourceID: sourceID, pageID: pageID))
    }

    var body: some View {
        ScrollView {
            if let page = viewModel.page {
                FunctionPageContent(sourceID: sourceID, page: page)
            }
        }
        .navigationTitle(viewModel.page?.scheme?.title ?? title)
        .navigationBarTitleDisplayMode(.inline)
        .hidesFloatingTabBar()
        .task { await viewModel.load() }
        .overlay {
            if viewModel.page == nil {
                if let message = viewModel.errorMessage {
                    ContentUnavailableView("无法打开页面", systemImage: "exclamationmark.triangle", description: Text(message))
                } else {
                    ProgressView()
                }
            }
        }
    }
}
