import SwiftUI

/// 历史页：本地浏览记录，最近读的在前。
///
/// 这份内容原先是首页列表头部的「继续阅读」横条，跟着列表往上滚；独立成标签页后
/// 每条能多显示读完的章节与时间，也不再挤占首页第一屏。
struct HistoryView: View {
    private var history = ReadingHistoryStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    ContentUnavailableView(
                        "暂无浏览记录",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("读过的漫画会出现在这里")
                    )
                } else {
                    list
                }
            }
            .navigationTitle(AppTab.history.title)
            .appNavigationDestinations()
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(history.entries) { entry in
                    // 与「继续阅读」一样先进详情页：直接续读会跳过封面与章节选择
                    NavigationLink(value: AppRoute.comicDetail(sourceID: entry.source, comicID: entry.comicID)) {
                        row(for: entry)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("删除记录", role: .destructive) { history.remove(entry) }
                    }

                    Divider().padding(.leading, AppTheme.Size.listThumbnail.width + 12)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.page)
        }
    }

    private func row(for entry: ReadingHistoryEntry) -> some View {
        ComicRowLayout {
            PluginImageView(sourceID: entry.source, url: entry.coverURL)
        } details: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title.convertedChinese)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                if let chapterName = entry.chapterName, !chapterName.isEmpty {
                    Text(chapterName.convertedChinese)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(entry.updatedAt.formatted(date: .numeric, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    HistoryView()
}
