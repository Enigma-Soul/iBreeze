import SwiftUI

/// 二级页面用它告诉根视图：这一屏不要底部标签栏，否则会和页面自己的工具栏叠在一起。
private struct HidesFloatingTabBarKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// 详情页、阅读页这类推入的页面挂上它
    func hidesFloatingTabBar() -> some View {
        preference(key: HidesFloatingTabBarKey.self, value: true)
    }

    /// 挂在根视图上，接收子页面的隐藏请求
    func observesFloatingTabBarVisibility(_ onChange: @escaping (Bool) -> Void) -> some View {
        onPreferenceChange(HidesFloatingTabBarKey.self, perform: onChange)
    }
}
