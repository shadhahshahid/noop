import SwiftUI
import StrandDesign

// Personal fork: the one score ring used by the hero of Today (Charge) and of Sleep.
//
// Today drew Charge as a thin flat arc while Sleep drew its score in upstream's thick, banded
// `LiquidScoreGauge`, so the two main scores of the app looked like they came from two apps. Both
// heroes now draw this ring: a plain track, one flat arc in the score's colour, the number in the
// middle and a short caption under it. Only how a score is drawn lives here, never the score.
struct ForkScoreRing: View {
    /// The score on a 0 to `maxValue` scale, or nil for "no score".
    let score: Double?
    let tint: Color
    /// A short word under the number, drawn in capitals ("CHARGE").
    let caption: String
    /// The arc is drawn at zero until this is true, then grows to the score. Lets a screen hold the
    /// ring back until its data has loaded.
    var revealed: Bool = true
    var maxValue: Double = 100

    static let size: CGFloat = 176
    static let lineWidth: CGFloat = 12

    /// Set on first appearance, so the arc grows in rather than being drawn full at once.
    @State private var appeared = false

    private var fraction: Double { min(1, max(0, (score ?? 0) / maxValue)) }
    private var shown: Bool { revealed && appeared }

    var body: some View {
        ZStack {
            Circle()
                .stroke(StrandPalette.surfaceInset, lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: shown ? fraction : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: shown)
                .animation(.easeOut(duration: 0.5), value: fraction)
            VStack(spacing: 2) {
                Text(verbatim: score.map { String(Int($0.rounded())) } ?? "–")
                    .font(StrandFont.rounded(64, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: caption.uppercased())
                    .font(StrandFont.overline)
                    .tracking(1.6)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .onAppear { appeared = true }
    }
}
