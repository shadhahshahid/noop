import SwiftUI

// Personal fork: flat versions of the small ring and the bar.
//
// Upstream draws every progress ring and bar with a banded dark-and-light gradient
// (`LiquidRender.progressGradient`). On a large hero ring that reads as polished metal; on a
// 30-point ring in a list row, or a 9-point bar in a tile, it reads as two colours fighting.
// `LiquidRender` asks this file how to draw the small ones; hero-size rings are left as upstream
// draws them. Only how a value is drawn changes here, never the value.
enum ForkFlatMarks {
    /// Rings at least this wide (in points) keep upstream's sculpted, banded look.
    static let heroDiameter: CGFloat = 64

    /// Bars are always small, so their fill is always one flat colour.
    static let flatBars = true

    /// Whether a ring drawn into `size` is a small one.
    static func isSmallRing(_ size: CGSize) -> Bool {
        min(size.width, size.height) < heroDiameter
    }

    /// A plain ring: a faint track in the ring's own colour, and one flat arc from the top,
    /// clockwise, for `level` (0...1). No disc, rim, shadow or gradient.
    static func ring(_ context: GraphicsContext, size: CGSize, level: Double, tint: Color) {
        let diameter = max(2, min(size.width, size.height) - 2)
        let lineWidth = max(3, diameter * 0.13)
        let radius = (diameter - lineWidth) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        var track = Path()
        track.addArc(center: center, radius: radius, startAngle: .degrees(0),
                     endAngle: .degrees(360), clockwise: false)
        context.stroke(track, with: .color(tint.opacity(0.20)), lineWidth: lineWidth)

        let filled = max(0, min(1, level))
        guard filled > 0.004 else { return }
        var arc = Path()
        arc.addArc(center: center, radius: radius, startAngle: .degrees(-90),
                   endAngle: .degrees(-90 + 360 * filled), clockwise: false)
        context.stroke(arc, with: .color(tint),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}

// Personal fork: layout numbers for the Key metrics tiles on Today.
enum ForkTodayTileMetrics {
    /// Height reserved for a tile's label, value and one-line caption at standard text size, so
    /// the bar below lands at the same height whether or not a tile has a caption. Larger text
    /// sizes grow past it; nothing is clipped.
    static let headBlockMinHeight: CGFloat = 74
}
