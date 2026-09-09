import SwiftUI

public extension View {
    @ViewBuilder
    func settingsScrollEdgeEffect() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .vertical)
                .scrollEdgeEffectHidden(false, for: .vertical)
        } else {
            self
        }
        #else
        self
        #endif
    }

    func subtleScrollbars() -> some View {
        scrollIndicators(.automatic)
    }
}
