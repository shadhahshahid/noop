//  ForkRunViews.swift
//  Personal fork only (not upstream).
//
//  The run coach on screen: the live card shown during a coached run, and the sheet that sets a run
//  up. Neither computes anything; they draw a `ForkRunCoachDisplay` and edit a `ForkRunPlan`.

import SwiftUI
import StrandDesign

// MARK: - Live coach card

/// The big "where am I against my target" card at the top of the in-exercise screen.
struct ForkRunCoachCard: View {
    let display: ForkRunCoachDisplay

    private var stateColor: Color {
        switch display.state {
        case .inTarget: return StrandPalette.statusPositive
        case .below: return StrandPalette.statusWarning
        case .above: return StrandPalette.statusCritical
        case .waiting, .resting, .paused, .done: return StrandPalette.textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: display.title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: NoopMetrics.space2)
                Text(verbatim: display.target)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                Text(verbatim: display.value)
                    .font(StrandFont.rounded(84, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(verbatim: display.unit)
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: 0)
            }

            HStack(spacing: NoopMetrics.space2) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 10, height: 10)
                Text(verbatim: display.message)
                    .font(StrandFont.rounded(19, weight: .semibold))
                    .foregroundStyle(stateColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let footnote = display.footnote {
                Text(verbatim: footnote)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(NoopMetrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}

/// Shows the coach card while a coached run is in progress, and nothing otherwise. A leaf with its
/// own observation, so a new reading redraws this card and not the screen around it.
struct ForkRunCoachPanel: View {
    @ObservedObject private var coach = ForkRunCoach.shared

    var body: some View {
        if let display = coach.display {
            ForkRunCoachCard(display: display)
        }
    }
}

// MARK: - Run setup

/// Choose what the run is for, then start it. Opens on the plan used last time.
struct ForkRunSetupSheet: View {
    let onStart: (ForkRunPlan) -> Void

    @EnvironmentObject private var model: AppModel
    @State private var plan: ForkRunPlan

    /// `initialPlan` is for previews and screenshots; the app opens on the plan used last time.
    init(initialPlan: ForkRunPlan? = nil, onStart: @escaping (ForkRunPlan) -> Void) {
        self.onStart = onStart
        _plan = State(initialValue: initialPlan ?? ForkRunPlan.loadLast())
    }

    private var zoneRangeText: String {
        guard let zone = model.profile.hrZoneSet.zones.first(where: { $0.number == plan.zone }) else { return "" }
        if zone.number == 5 { return String(localized: "\(Int(zone.lower.rounded())) bpm and above") }
        return String(localized: "\(Int(zone.lower.rounded())) to \(Int(zone.upper.rounded()) - 1) bpm")
    }

    private var paceBandText: String {
        let low = ForkRunMath.paceText(Double(plan.paceSecPerKm - plan.paceToleranceSec))
        let high = ForkRunMath.paceText(Double(plan.paceSecPerKm + plan.paceToleranceSec))
        return String(localized: "Counts as on pace from \(low) to \(high) /km")
    }

    private var intervalTotalText: String {
        let total = plan.intervalPlan.totalSec
        return String(localized: "\(plan.reps) reps, \(ForkRunMath.clockText(Double(total))) in all")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.space5) {
                Text("Run")
                    .font(StrandFont.rounded(28))
                    .foregroundStyle(StrandPalette.textPrimary)

                Picker("Mode", selection: $plan.mode) {
                    ForEach(ForkRunMode.allCases) { mode in
                        Text(verbatim: mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(verbatim: plan.mode.blurb)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                switch plan.mode {
                case .zone:
                    panel {
                        row("Zone", value: String(localized: "Zone \(plan.zone)"))
                        Picker("Zone", selection: $plan.zone) {
                            ForEach(1...5, id: \.self) { zone in Text(verbatim: "\(zone)").tag(zone) }
                        }
                        .pickerStyle(.segmented)
                        caption(zoneRangeText)
                    }
                case .pace:
                    panel {
                        paceControls
                    }
                case .intervals:
                    panel {
                        stepper("Reps", value: "\(plan.reps)", down: { plan.reps -= 1 }, up: { plan.reps += 1 })
                        divider
                        stepper("Work", value: ForkRunMath.clockText(Double(plan.workSec)),
                                down: { plan.workSec -= 15 }, up: { plan.workSec += 15 })
                        divider
                        stepper("Recovery", value: ForkRunMath.clockText(Double(plan.restSec)),
                                down: { plan.restSec -= 15 }, up: { plan.restSec += 15 })
                        caption(intervalTotalText)
                    }
                    panel {
                        paceControls
                    }
                case .free:
                    EmptyView()
                }

                if plan.mode != .free {
                    panel {
                        Toggle(isOn: $plan.buzz) {
                            Text("Buzz the strap")
                                .font(StrandFont.body)
                                .foregroundStyle(StrandPalette.textPrimary)
                        }
                        .tint(StrandPalette.accent)
                        caption(String(localized: "Two short buzzes: pick it up. Three long: ease off. One short: back on target."))
                    }
                }

                NoopButton("Start run", systemImage: "figure.run", kind: .primary, fullWidth: true) {
                    onStart(plan.clamped)
                }
            }
            .padding(NoopMetrics.space5)
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        // Keep every value inside its allowed range however the steppers are pressed.
        .onChangeCompat(of: plan) { changed in
            let clamped = changed.clamped
            if clamped != changed { plan = clamped }
        }
    }

    // MARK: Pieces

    @ViewBuilder private var paceControls: some View {
        stepper("Target pace", value: String(localized: "\(ForkRunMath.paceText(Double(plan.paceSecPerKm))) /km"),
                down: { plan.paceSecPerKm += 5 }, up: { plan.paceSecPerKm -= 5 },
                downLabel: "Slower", upLabel: "Faster")
        divider
        stepper("Margin", value: String(localized: "± \(plan.paceToleranceSec) s"),
                down: { plan.paceToleranceSec -= 5 }, up: { plan.paceToleranceSec += 5 })
        caption(paceBandText)
    }

    private var divider: some View {
        Rectangle().fill(StrandPalette.hairline).frame(height: 1)
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            content()
        }
        .padding(NoopMetrics.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: 22))
    }

    private func row(_ label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            Text(verbatim: value).font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textSecondary)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text)
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A labelled value with a minus and a plus button, each a full 44-point target.
    private func stepper(_ label: LocalizedStringKey, value: String, down: @escaping () -> Void,
                         up: @escaping () -> Void, downLabel: LocalizedStringKey = "Less",
                         upLabel: LocalizedStringKey = "More") -> some View {
        HStack(spacing: NoopMetrics.space2) {
            Text(label).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
            Spacer(minLength: NoopMetrics.space2)
            Text(verbatim: value)
                .font(StrandFont.rounded(19, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(StrandPalette.textPrimary)
            stepButton("minus", action: down).accessibilityLabel(downLabel)
            stepButton("plus", action: up).accessibilityLabel(upLabel)
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(StrandPalette.surfaceOverlay))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
/// DEBUG-only sample states for the screenshot workflow. Sample numbers only.
enum ForkRunCoachSamples {
    static let inZone = ForkRunCoachDisplay(title: "Zone 2", target: "124 to 137 bpm", value: "131", unit: "bpm",
                                            state: .inTarget, message: "In zone", footnote: "In target 12:40 of 18:05")
    static let below = ForkRunCoachDisplay(title: "Zone 2", target: "124 to 137 bpm", value: "118", unit: "bpm",
                                           state: .below, message: "Below zone: pick it up", footnote: "In target 12:40 of 18:20")
    static let above = ForkRunCoachDisplay(title: "Pace", target: "5:50 to 6:10 /km", value: "5:31", unit: "/km",
                                           state: .above, message: "Too fast: ease off", footnote: "In target 6:10 of 9:45")
    static let resting = ForkRunCoachDisplay(title: "Recovery 3 of 5", target: "4:50 to 5:10 /km", value: "7:42", unit: "/km",
                                             state: .resting, message: "Recovering, 0:45 left", footnote: "In target 5:30 of 6:00")
}

/// DEBUG-only: the coach card in one fixed state, so the screenshot workflow can capture each state
/// without a strap or a run.
struct ForkRunCoachDemo: View {
    let display: ForkRunCoachDisplay

    var body: some View {
        ScrollView {
            ForkRunCoachCard(display: display)
                .padding(NoopMetrics.space5)
        }
    }
}
#endif
