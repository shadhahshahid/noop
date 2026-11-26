import SwiftUI
import StrandDesign

// Personal fork: a plain symbol at the head of a list row on Today, in place of a small ring.
//
// Upstream led each Recovery vitals and Your cards row with a small ring filled to the row's value
// over a fixed constant (HRV over 120, resting heart rate over 100), and some rings were filled to a
// fixed half whatever the value (Fitness Age, VO₂ max). A ring around "34 yrs" measures nothing, so
// the row now leads with a symbol that says what the row is, in the row's own colour. The value and
// the link beside it are unchanged.
//
// The symbol travels through the environment (`forkRowSymbol`), so the upstream row builders keep
// their signatures: the caller sets the symbol on the row, the row's leading slot reads it.

/// A symbol on a faint disc of its own colour.
struct ForkRowSymbol: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.16)))
            .accessibilityHidden(true)
    }
}

/// The leading slot of a row: draws the symbol the row was given through `forkRowSymbol`.
struct ForkRowSymbolSlot: View {
    @Environment(\.forkRowSymbol) private var symbol
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        ForkRowSymbol(systemName: symbol ?? ForkRowSymbols.fallback, tint: tint, size: size)
    }
}

/// Which symbol each row on Today leads with.
enum ForkRowSymbols {
    /// Used for a row that was given no symbol.
    static let fallback = "circle.fill"

    static let hrv = "waveform.path.ecg"
    static let restingHr = "heart.circle.fill"
    static let respiratory = "lungs.fill"

    /// The symbol for a Your cards row. Where the Key metrics tiles show the same measure, the
    /// symbol is the one the tile uses, so one measure has one symbol on the screen.
    static func symbol(for card: DashboardCard) -> String {
        switch card {
        case .hrv: return hrv
        case .restingHr: return restingHr
        case .respiratory: return respiratory
        case .steps, .stepsAverage30: return "figure.walk"
        case .stress: return "bolt.heart.fill"
        case .fitnessAge: return "hourglass"
        case .vo2max: return "figure.run"
        case .vitality: return "sparkles"
        case .bloodOxygen: return "drop.fill"
        case .skinTemp: return "thermometer.medium"
        case .sleep: return "moon.stars.fill"
        case .calories: return "flame.fill"
        case .hydration: return "waterbottle.fill"
        case .coupled: return "rectangle.split.2x1.fill"
        case .coach: return "bubble.left.and.bubble.right.fill"
        }
    }
}

private struct ForkRowSymbolKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The symbol a Today list row leads with (see `ForkRowSymbolSlot`).
    var forkRowSymbol: String? {
        get { self[ForkRowSymbolKey.self] }
        set { self[ForkRowSymbolKey.self] = newValue }
    }
}
