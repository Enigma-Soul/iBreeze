import SwiftUI

extension View {
    /// 标签栏随列表下滚收起、上滚展开。iOS 26 起由系统负责，更早的系统一直显示
    @ViewBuilder
    func minimizesTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
