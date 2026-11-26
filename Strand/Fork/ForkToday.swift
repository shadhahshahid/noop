//  ForkToday.swift
//  Personal fork only (not upstream).
//
//  The redesigned Today hero: ONE score (Charge) with a one-word verdict and a plain sentence, the
//  few things driving it, Effort so far against today's target band, and one-tap starts for the
//  sessions the wearer actually does.
//
//  Nothing here computes a score. Every value is resolved by LiquidTodayView from the same state its
//  other read-outs use and handed in as a plain value, so this layout cannot disagree with the rest
//  of the app. Keeping the views in their own file also keeps the edits to upstream files small.

import SwiftUI
import StrandDesign

// MARK: - Plain values handed in by the host screen

/// One thing shaping today's Charge, already formatted for display.
struct ForkDriver: Identifiable, Equatable {
    enum Tone: Equatable { case good, neutral, watch, bad }
    let id: String
    let label: String
    let value: String
    let tone: Tone

    var color: Color {
        switch tone {
        case .good:    return StrandPalette.statusPositive
        case .neutral: return StrandPalette.textTertiary
        case .watch:   return StrandPalette.statusWarning
        case .bad:     return StrandPalette.statusCritical
        }
    }

    /// The state as a shape, so it does not rest on colour alone. Not an arrow: for resting heart
    /// rate "good" means lower, and an arrow would be read as the direction the number moved.
    var symbol: String {
        switch tone {
        case .good:    return "checkmark.circle.fill"
        case .neutral: return "minus.circle.fill"
        case .watch:   return "exclamationmark.circle.fill"
        case .bad:     return "exclamationmark.triangle.fill"
        }
    }

    /// The state in a word, for VoiceOver.
    var stateWord: String {
        switch tone {
        case .good:    return String(localized: "Good")
        case .neutral: return String(localized: "Usual")
        case .watch:   return String(localized: "Watch")
        case .bad:     return String(localized: "Low")
        }
    }
}

/// Everything the hero draws. Effort values are already on the wearer's chosen display scale.
struct ForkTodayHeroModel: Equatable {
    var charge: Double?
    var verdict: String
    var sentence: String
    /// Shown under the sentence when Charge is not this day's own score ("Last night · Fri 13").
    var caption: String?
    var drivers: [ForkDriver]
    /// Longer lines revealed by tapping the sentence.
    var details: [String]
    var effort: Double?
    var effortMax: Double
    var effortDecimals: Int
    var effortTarget: ClosedRange<Double>?
}

// MARK: - Hero card

struct ForkTodayHero: View {
    let model: ForkTodayHeroModel
    var surfaceOpacity: Double = 1
    var animated: Bool = true

    @State private var expanded = false

    private static let ringSize: CGFloat = 176
    private static let ringWidth: CGFloat = 12

    /// State colour for the score: the same three bands the Effort target is derived from.
    private var chargeColor: Color { Self.stateColor(charge: model.charge) }

    /// The one place Charge is turned into a state colour. The hero ring and the Charge tile under
    /// it both ask here, so the same score cannot be amber in one place and green in another.
    static func stateColor(charge: Double?) -> Color {
        guard let charge else { return StrandPalette.textTertiary }
        if charge >= 67 { return StrandPalette.statusPositive }
        if charge >= 34 { return StrandPalette.statusWarning }
        return StrandPalette.statusCritical
    }

    private var chargeSpokenLabel: String {
        if let charge = model.charge {
            return "Charge \(Int(charge.rounded())) of 100. \(model.verdict)."
        }
        return "Charge. \(model.verdict)."
    }

    var body: some View {
        VStack(spacing: NoopMetrics.space5) {
            NavigationLink(value: TabRoute.metric(HeroRingMetric.charge)) { ring }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: chargeSpokenLabel))
                .accessibilityHint("Opens the Charge detail")

            verdictBlock

            if !model.drivers.isEmpty {
                HStack(alignment: .top, spacing: NoopMetrics.space2) {
                    ForEach(model.drivers) { driver in
                        driverCell(driver)
                    }
                }
            }

            Rectangle()
                .fill(StrandPalette.hairline)
                .frame(height: 1)

            NavigationLink(value: TabRoute.metric(HeroRingMetric.effort)) { effortBlock }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the Effort detail")
        }
        .padding(.vertical, NoopMetrics.space6)
        .padding(.horizontal, NoopMetrics.space5)
        .frame(maxWidth: .infinity)
        .background(NoopPanelSurface(cornerRadius: 28, surfaceOpacity: surfaceOpacity))
    }

    // MARK: Ring

    private var ring: some View {
        let fraction = min(1, max(0, (model.charge ?? 0) / 100))
        return ZStack {
            Circle()
                .stroke(StrandPalette.surfaceInset, lineWidth: Self.ringWidth)
            Circle()
                .trim(from: 0, to: animated ? fraction : 0)
                .stroke(chargeColor, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: animated)
                .animation(.easeOut(duration: 0.5), value: fraction)
            VStack(spacing: 2) {
                Text(verbatim: model.charge.map { String(Int($0.rounded())) } ?? "–")
                    .font(StrandFont.rounded(64, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("CHARGE")
                    .font(StrandFont.overline)
                    .tracking(1.6)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .contentShape(Circle())
    }

    // MARK: Verdict

    private var verdictBlock: some View {
        Button {
            guard !model.details.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            VStack(spacing: NoopMetrics.space2) {
                Text(verbatim: model.verdict)
                    .font(StrandFont.rounded(26, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: model.sentence)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption = model.caption {
                    Text(verbatim: caption)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                if expanded {
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        ForEach(model.details, id: \.self) { line in
                            Text(verbatim: line)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, NoopMetrics.space1)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Drivers

    private func driverCell(_ driver: ForkDriver) -> some View {
        VStack(spacing: NoopMetrics.space1) {
            HStack(spacing: 6) {
                Image(systemName: driver.symbol)
                    .font(StrandFont.caption)
                    .imageScale(.small)
                    .foregroundStyle(driver.color)
                    .accessibilityLabel(driver.stateWord)
                Text(verbatim: driver.label)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(verbatim: driver.value)
                .font(StrandFont.rounded(17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Effort against the target band

    private func number(_ value: Double) -> String {
        model.effortDecimals == 0
            ? String(Int(value.rounded()))
            : String(format: "%.\(model.effortDecimals)f", value)
    }

    /// Where today's Effort sits against the band, in words.
    private var effortNote: (text: String, color: Color) {
        guard let effort = model.effort else {
            return (String(localized: "No Effort recorded yet"), StrandPalette.textTertiary)
        }
        guard let target = model.effortTarget else {
            return (String(localized: "Target appears once Charge is scored"), StrandPalette.textTertiary)
        }
        if effort < target.lowerBound {
            return (String(localized: "\(number(target.lowerBound - effort)) to reach your target"),
                    StrandPalette.textSecondary)
        }
        if effort <= target.upperBound {
            return (String(localized: "In your target"), StrandPalette.statusPositive)
        }
        return (String(localized: "Above your target"), StrandPalette.statusWarning)
    }

    private var effortBlock: some View {
        let note = effortNote
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Effort so far")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: NoopMetrics.space2)
                if let target = model.effortTarget {
                    Text(verbatim: String(localized: "Target \(number(target.lowerBound)) to \(number(target.upperBound))"))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                Text(verbatim: model.effort.map(number) ?? "–")
                    .font(StrandFont.rounded(30, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: note.text)
                    .font(StrandFont.caption)
                    .foregroundStyle(note.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                let maxValue = max(1, model.effortMax)
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset)
                    if let target = model.effortTarget {
                        Capsule()
                            .fill(StrandPalette.textTertiary.opacity(0.5))
                            .frame(width: max(0, (target.upperBound - target.lowerBound) / maxValue * width))
                            .offset(x: min(width, max(0, target.lowerBound / maxValue * width)))
                    }
                    if let effort = model.effort, effort > 0 {
                        Capsule()
                            .fill(StrandPalette.textPrimary)
                            .frame(width: max(8, min(1, effort / maxValue) * width))
                    }
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - One-tap starts

/// Four one-tap starts for the sessions the wearer does most, plus a way into the full list. A tap
/// starts the session through the same `AppModel.startWorkout` and in-exercise view the upstream
/// Start control uses, so a session started here is identical to one started anywhere else.
struct ForkQuickStarts: View {
    var surfaceOpacity: Double = 1
    @EnvironmentObject var model: AppModel
    @State private var showLiveWorkout = false
    @State private var showPicker = false
    @State private var showRunSetup = false

    private static let runSport = "Running"

    private struct Start: Identifiable {
        let title: LocalizedStringKey
        /// The `WorkoutCatalog` sport name the session is recorded under.
        let sport: String
        let symbol: String
        var id: String { sport }
    }

    private static let starts: [Start] = [
        Start(title: "HIIT", sport: "HIIT", symbol: "flame.fill"),
        Start(title: "Run", sport: "Running", symbol: "figure.run"),
        Start(title: "Yoga", sport: "Yoga", symbol: "figure.yoga"),
        Start(title: "Stretch", sport: "Stretching", symbol: "figure.flexibility"),
    ]

    var body: some View {
        // A VStack rather than a Group: the sheets below must stay attached while the tiles are hidden
        // during a session, or the in-exercise view would be torn down the moment the session starts.
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            if model.activeWorkout == nil {
                HStack(alignment: .firstTextBaseline) {
                    Text("START")
                        .font(StrandFont.overline)
                        .tracking(1.6)
                        .foregroundStyle(StrandPalette.textTertiary)
                    Spacer()
                    Button { showPicker = true } label: {
                        Text("All activities")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .forkTapTarget()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 2)

                HStack(spacing: NoopMetrics.space2) {
                    ForEach(Self.starts) { start in
                        Button {
                            StrandHaptic.commit.play()
                            // A run first asks what it is for (zone, pace, intervals or free); the
                            // other sessions have nothing to set up and start at once.
                            if start.sport == Self.runSport {
                                showRunSetup = true
                            } else {
                                model.startWorkout(sport: start.sport)
                                showLiveWorkout = true
                            }
                        } label: {
                            VStack(spacing: NoopMetrics.space2) {
                                Image(systemName: start.symbol)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .frame(height: 24)
                                Text(start.title)
                                    .font(StrandFont.caption.weight(.semibold))
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, NoopMetrics.space4)
                            .background(NoopPanelSurface(cornerRadius: 20, surfaceOpacity: surfaceOpacity))
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Start \(start.sport)"))
                    }
                }
            }
        }
        .sheet(isPresented: $showLiveWorkout) {
            LiveWorkoutView(onClose: { showLiveWorkout = false })
                .environmentObject(model.live)
        }
        .sheet(isPresented: $showRunSetup) {
            ForkRunSetupSheet { plan in
                showRunSetup = false
                model.startWorkout(sport: Self.runSport)
                ForkRunCoach.shared.begin(plan)
                Task {
                    // Let the setup sheet finish closing before the live screen is presented.
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    showLiveWorkout = true
                }
            }
            .environmentObject(model)
        }
        .workoutSelectionCover(isPresented: $showPicker) {
            StartWorkoutSheet { name in
                model.startWorkout(sport: name)
                showLiveWorkout = true
            }
        }
    }
}
