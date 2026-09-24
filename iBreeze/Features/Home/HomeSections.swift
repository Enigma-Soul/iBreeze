import SwiftUI

/// 插件入口横滑区，点击进入对应插件
struct PluginRowSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "插件")
            EmptyHint(icon: "puzzlepiece.extension", text: "还没有安装插件，去「设置 → 插件管理」添加")
        }
    }
}

/// 浏览记录横滑区
struct BrowsingHistorySection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "浏览记录")
            EmptyHint(icon: "clock.arrow.circlepath", text: "还没有浏览记录")
        }
    }
}

/// 插件源推荐漫画，插件未提供推荐内容时隐藏
struct RecommendedComicsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "推荐漫画")
            EmptyHint(icon: "square.grid.2x2", text: "当前插件没有提供推荐内容")
        }
    }
}
