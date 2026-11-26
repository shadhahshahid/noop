import SwiftUI
import StrandDesign

// Personal fork: keeps scrolled content from drawing under the clock.
//
// Each tab's first screen hides the system navigation bar and draws its own header inside the
// scrolling content, so once scrolled, rows pass straight under the status bar and collide with
// the time and battery. This covers the status-bar area and fades out just below it. It draws
// nothing else and takes no touches.
//
// In the dark theme the cover is the canvas colour, which is what already sits behind the header,
// so it cannot be seen until something scrolls under it. In the light theme the top of a screen
// is a tinted sky that changes with the hour, so no single colour matches it; there the cover is
// the system's own frosted material, as under a navigation bar.
private struct ForkStatusBarScrim: ViewModifier {
    /// How far below the status bar the fade runs.
    private static let fade: CGFloat = 14

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            GeometryReader { proxy in
                let inset = proxy.safeAreaInsets.top
                let shape = LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.94), location: inset / max(1, inset + Self.fade)),
                        .init(color: .black.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Group {
                    if scheme == .dark {
                        Rectangle().fill(StrandPalette.surfaceBase)
                    } else {
                        Rectangle().fill(.ultraThinMaterial)
                    }
                }
                .mask(shape)
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
