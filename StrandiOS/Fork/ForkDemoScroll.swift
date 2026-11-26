#if DEBUG
import SwiftUI
import UIKit

/// DEBUG-only screenshot aid. `--demo-scroll-page <N>` scrolls the visible screen down by N
/// screenfuls shortly after launch, so the screenshot workflow can photograph what sits below
/// the first screenful (see `Tools/custom-ios-screenshots.sh`, names such as `shell+3`).
///
/// It moves the largest vertical scroll view of the key window and nothing else: no data is
/// read or written, and the whole file is stripped from Release builds.
enum ForkDemoScroll {
    /// The page named by `--demo-scroll-page <N>`, or nil when the argument is absent or not positive.
    static var requestedPage: Int? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--demo-scroll-page"), i + 1 < args.count,
              let page = Int(args[i + 1]), page > 0 else { return nil }
        return page
    }

    /// Scrolls once the first content has drawn, and twice more in case the content grew after
    /// its data loaded. Does nothing when the launch argument is absent.
    static func applyLaunchArgsIfNeeded() {
        guard let page = requestedPage else { return }
        Task { @MainActor in
            for wait in [3.0, 2.0, 2.0] {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                scroll(toPage: page)
            }
        }
    }

    @MainActor
    private static func scroll(toPage page: Int) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first,
              let scrollView = largestVerticalScrollView(in: window) else { return }
        let insets = scrollView.adjustedContentInset
        let visible = scrollView.bounds.height - insets.top - insets.bottom
        // A tenth of each screenful repeats on the next picture, so nothing falls in a gap.
        let step = max(1, visible * 0.9)
        let top = -insets.top
        let bottom = max(top, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom)
        let y = min(bottom, top + CGFloat(page) * step)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
    }

    /// The page's own scroll view: on screen, taller than it shows, and close to full width, which
    /// rules out the horizontal chip rows and small nested pickers.
    @MainActor
    private static func largestVerticalScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        var pending: [UIView] = [root]
        while let view = pending.popLast() {
            if view.isHidden { continue }
            if let candidate = view as? UIScrollView,
               candidate.window != nil,
               candidate.contentSize.height > candidate.bounds.height + 1,
               candidate.bounds.width >= root.bounds.width * 0.6 {
                let area = candidate.bounds.width * candidate.bounds.height
                if let current = best {
                    if area > current.bounds.width * current.bounds.height { best = candidate }
                } else {
                    best = candidate
                }
            }
            pending.append(contentsOf: view.subviews)
        }
        return best
    }
}
#endif
