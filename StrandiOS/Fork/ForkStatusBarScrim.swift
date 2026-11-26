import SwiftUI
import StrandDesign

// Personal fork: keeps scrolled content from drawing under the clock.
//
// Each tab's first screen hides the system navigation bar and draws its own header inside the
// scrolling content, so once scrolled, rows pass straight under the status bar and collide with
// the time and battery. This lays the canvas colour over the status-bar area, fading out just
// below it. It draws nothing else and takes no touches.
private struct ForkStatusBarScrim: ViewModifier {
    /// How far below the status bar the fade runs.
    private static let fade: CGFloat = 14

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            GeometryReader { proxy in
                let inset = proxy.safeAreaInsets.top
                LinearGradient(
                    stops: [
                        .init(color: StrandPalette.surfaceBase, location: 0),
                        .init(color: StrandPalette.surfaceBase.opacity(0.94),
                              location: inset / max(1, inset + Self.fade)),
                        .init(color: StrandPalette.surfaceBase.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: inset + Self.fade)
                .offset(y: -inset)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Covers the status-bar area of a tab's first screen with the canvas colour.
    func forkStatusBarScrim() -> some View {
        modifier(ForkStatusBarScrim())
    }
}
