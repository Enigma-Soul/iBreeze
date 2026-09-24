import SwiftUI
import Observation

/// 首页插件入口：图标横滑，点开后选择插件提供的入口
struct PluginRowSection: View {
    @Environment(PluginRegistry.self) private var registry
    @State private var selectedPlugin: InstalledPlugin?

    private let tileSize: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "插件")

            if registry.installed.isEmpty {
                EmptyHint(icon: "puzzlepiece.extension", text: "还没有安装插件，去「设置 → 插件管理」添加")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.grid) {
                        ForEach(registry.installed) { plugin in
                            Button {
                                selectedPlugin = plugin
                            } label: {
                                tile(for: plugin)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.page)
                }
            }
        }
        .sheet(item: $selectedPlugin) { plugin in
            PluginEntriesSheet(plugin: plugin)
        }
    }

    private func tile(for plugin: InstalledPlugin) -> some View {
        VStack(spacing: 6) {
            AsyncImage(url: plugin.iconURL.flatMap(URL.init(string:))) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "puzzlepiece.extension")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(width: tileSize, height: tileSize)
            .glassSurface(in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(plugin.name)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: tileSize + 12)
        }
    }
}

/// 插件入口列表：每个入口对应插件 `getInfo().function` 里的一项
struct PluginEntriesSheet: View {
    let plugin: InstalledPlugin

    @Environment(\.dismiss) private var dismiss
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if plugin.functions.isEmpty {
                    ContentUnavailableView(
                        "该插件没有提供入口",
                        systemImage: "questionmark.circle",
                        description: Text("可以在搜索页直接搜索它的内容")
                    )
                } else {
                    ForEach(plugin.functions) { item in
                        if let route = route(for: item) {
                            NavigationLink(value: route) {
                                Label(item.title, systemImage: icon(for: item.action.type))
                            }
                        } else {
                            Label(item.title, systemImage: icon(for: item.action.type))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(plugin.name)
            .navigationBarTitleDisplayMode(.inline)
            .appNavigationDestinations()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    /// 把插件的入口动作映射成 App 内路由
    private func route(for item: PluginFunctionItem) -> AppRoute? {
        guard let payload = item.action.payload else { return nil }

        switch item.action.type {
        case "openComicList":
            guard let scene = payload.scene else { return nil }
            return .comicList(
                sourceID: plugin.uuid,
                fnPath: scene.body.request.fnPath,
                title: scene.title,
                core: scene.body.request.core,
                extern: scene.body.request.extern
            )

        case "openComicDetail":
            guard let comicID = payload.comicId else { return nil }
            return .comicDetail(sourceID: plugin.uuid, comicID: comicID)

        default:
            return nil
        }
    }

    private func icon(for type: String) -> String {
        switch type {
        case "openComicList": "list.bullet.rectangle"
        case "openComicDetail": "book"
        case "openSearch": "magnifyingglass"
        case "openWeb": "safari"
        default: "square.grid.2x2"
        }
    }
}

/// 首页浏览记录：最近读过的漫画
struct BrowsingHistorySection: View {
    private var history = ReadingHistoryStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "浏览记录")

            if history.entries.isEmpty {
                EmptyHint(icon: "clock.arrow.circlepath", text: "还没有浏览记录")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.grid) {
                        ForEach(history.entries) { entry in
                            NavigationLink(value: route(for: entry)) {
                                entryCard(entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.page)
                }
            }
        }
    }

    private func entryCard(_ entry: ReadingHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PluginImageView(sourceID: entry.source, url: entry.coverURL)
                .frame(width: 110, height: 146)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))

            Text(entry.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
        }
    }

    /// 有章节就直接续读，否则回详情页
    private func route(for entry: ReadingHistoryEntry) -> AppRoute {
        if let chapterID = entry.chapterID, !chapterID.isEmpty {
            return .reader(
                sourceID: entry.source,
                comicID: entry.comicID,
                chapterID: chapterID,
                chapterName: entry.chapterName ?? "",
                title: entry.title
            )
        }
        return .comicDetail(sourceID: entry.source, comicID: entry.comicID)
    }
}

/// 首页推荐漫画：取第一个插件的默认列表场景
struct RecommendedComicsSection: View {
    @Environment(PluginRegistry.self) private var registry
    @State private var items: [ComicListItem] = []
    @State private var sourceID: String?

    var body: some View {
        Group {
            if let sourceID, !items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "推荐漫画")
                    ComicPosterRow(items: items, sourceID: sourceID) { item in
                        AppRoute.comicDetail(sourceID: sourceID, comicID: item.id)
                    }
                }
            }
        }
        .task(id: registry.installed.map(\.uuid)) { await load() }
    }

    private func load() async {
        guard let plugin = registry.installed.first else {
            items = []
            sourceID = nil
            return
        }

        do {
            let source = try await registry.source(for: plugin.uuid)
            let scene = try await source.sceneBundle()
            guard let scene = Self.defaultScene(from: scene) else { return }

            let list = try await source.pagedList(fnPath: scene.fnPath, page: 1, core: scene.core)
            sourceID = plugin.uuid
            items = list.resolvedItems
        } catch {
            items = []
        }
    }

    /// 从场景包里取默认列表的请求参数
    private static func defaultScene(from bundle: JSONValue) -> (fnPath: String, core: JSONValue?)? {
        guard
            let request = bundle["data"]?["scene"]?["body"]?["request"],
            let fnPath = request["fnPath"]?.stringValue
        else { return nil }
        return (fnPath, request["core"])
    }
}
