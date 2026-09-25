import Observation
import SwiftUI

/// 悬浮标签栏的显隐状态。
///
/// 页面通过 `onScrollGeometryChange` 把滚动偏移喂进来，向下滚动时收起标签栏，
/// 向上滚动或回到顶部时展开。阈值做成不对称的，避免手指抖动导致反复横跳。
@MainActor
@Observable
final class TabBarVisibility {
    private static let hideThreshold: CGFloat = 12
    private static let showThreshold: CGFloat = -12
    private static let alwaysVisibleOffset: CGFloat = 40

    private(set) var isHidden = false
    private var lastOffset: CGFloat?

    func update(offset: CGFloat) {
        defer { lastOffset = offset }

        // 接近顶部时无条件显示，否则列表回弹后标签栏会一直藏着
        if offset < Self.alwaysVisibleOffset {
            isHidden = false
            return
        }

        guard let lastOffset else { return }
        let delta = offset - lastOffset

        if delta > Self.hideThreshold {
            isHidden = true
        } else if delta < Self.showThreshold {
            isHidden = false
        }
    }

    /// 切页或进入新页面时恢复显示
    func reset() {
        isHidden = false
        lastOffset = nil
    }
}

extension View {
    /// 挂在滚动容器上，把偏移喂给悬浮标签栏
    func tracksTabBarVisibility() -> some View {
        modifier(TabBarScrollTracking())
    }
}

private struct TabBarScrollTracking: ViewModifier {
    @Environment(TabBarVisibility.self) private var visibility

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            visibility.update(offset: offset)
        }
    }
}
