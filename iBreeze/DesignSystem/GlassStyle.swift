import SwiftUI

extension View {
    /// iOS 26 走液态玻璃，低版本回退到系统毛玻璃材质
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}
