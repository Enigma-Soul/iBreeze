import SwiftUI

/// 结果列表：首页、搜索、插件内搜索、插件列表页共用，自带触底续拉
struct ComicResultList: View {
    let items: [SourcedComic]
    let isLoading: Bool
    let hasReachedMax: Bool
    let loadMore: () -> Void
    /// 跟着列表一起滚走的头部（首页的「继续阅读」）
    var leading: AnyView? = nil
    /// 滚到顶后钉住的头部（入口选项卡）。首页靠它做到「划到插件图标那一行就固定」
    var pinnedHeader: AnyView? = nil
    /// 列表为空时显示什么（加载失败、没有结果…）。
    ///
    /// 它排在内容区顶部而不是盖成整屏居中的 overlay：后者会跑到固定头部后面，
    /// 看起来像浮在整屏正中。
    var emptyState: AnyView? = nil

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: pinnedHeader == nil ? [] : [.sectionHeaders]) {
                leading

                Section {
                    if items.isEmpty, let emptyState {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, AppTheme.Spacing.page)
                            .padding(.top, 48)
                    } else {
                        rows
                            .padding(.horizontal, AppTheme.Spacing.page)
                    }

                    footer
                } header: {
                    // 横向内边距留给各行，选项卡条自己带内边距，钉住时才能铺满整宽
                    pinnedHeader
                }
            }
        }
    }

    private var rows: some View {
        ForEach(items) { sourced in
            NavigationLink(value: AppRoute.comicDetail(sourceID: sourced.sourceID, comicID: sourced.item.id)) {
                ComicListRow(item: sourced.item, sourceID: sourced.sourceID)
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 88)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if isLoading {
            ProgressView().padding(.vertical, 20)
        } else if hasReachedMax, !items.isEmpty {
            Text("已经到底了")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 20)
        } else if !items.isEmpty {
            ProgressView()
                .padding(.vertical, 20)
                .onAppear(perform: loadMore)
        }
    }
}

extension ComicResultList {
    /// 单一来源页面的简写
    init(
        items: [ComicListItem],
        sourceID: String,
        isLoading: Bool,
        hasReachedMax: Bool,
        loadMore: @escaping () -> Void,
        leading: AnyView? = nil,
        pinnedHeader: AnyView? = nil,
        emptyState: AnyView? = nil
    ) {
        self.init(
            items: items.map { $0.sourced(from: sourceID) },
            isLoading: isLoading,
            hasReachedMax: hasReachedMax,
            loadMore: loadMore,
            leading: leading,
            pinnedHeader: pinnedHeader,
            emptyState: emptyState
        )
    }
}
