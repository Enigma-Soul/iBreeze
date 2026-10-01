import SwiftUI

extension View {
    /// 详情页、阅读页这类推入的页面挂上它：这一屏不要底部标签栏，
    /// 否则会和页面自己的工具栏叠在一起。
    ///
    /// 现在底栏是系统 `TabView` 的，所以直接用系统的 `.toolbar(.hidden, for: .tabBar)`，
    /// 不用再自己搭 PreferenceKey 往根视图传。
    func hidesFloatingTabBar() -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}
