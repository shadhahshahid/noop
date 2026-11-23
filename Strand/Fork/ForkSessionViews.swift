//  ForkSessionViews.swift
//  Personal fork only (not upstream).
//
//  The screens for a tracked session: the live card (HIIT, or the quiet one for Yoga and Stretch)
//  and the summary shown when a HIIT session ends. They draw values handed to them and save tags;
//  nothing is computed here.

import SwiftUI
import StrandDesign

// MARK: - Live card

struct ForkSessionCard: View {
    let display: ForkSessionDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: display.title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: NoopMetrics.space2)
                if let detail = display.detail {
                    Text(verbatim: detail)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                Text(verbatim: display.value)
                    .font(StrandFont.rounded(84, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("bpm")
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textSecondary)
                Spacer(minLength: 0)
            }

            HStack(spacing: NoopMetrics.space2) {
                if display.kind == .hiit {
                    Image(systemName: display.isWorking ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(display.isWorking ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(verbatim: display.message)
                    .font(StrandFont.rounded(19, weight: .semibold))
                    .foregroundStyle(display.isWorking ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let footnote = display.footnote, footnote != display.message {
                Text(verbatim: footnote)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(NoopMetrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}

/// Shows the session card while a tracked session runs, and nothing otherwise. A leaf with its own
/// observation, so a new reading redraws this card and not the screen around it.
struct ForkSessionPanel: View {
    @ObservedObject private var tracker = ForkSessionTracker.shared

    var body: some View {
        if let display = tracker.display {
            ForkSessionCard(display: display)
        }
    }
}

// MARK: - Summary

struct ForkSessionSummaryView: View {
    let summary: ForkSessionSummary
    let onDone: () -> Void

    @State private var note: ForkSessionNote

    init(summary: ForkSessionSummary, onDone: @escaping () -> Void) {
        self.summary = summary
        self.onDone = onDone
        _note = State(initialValue: ForkSessionNotes.note(forStart: summary.startTs) ?? ForkSessionNote())
    }

    private var tiles: [(label: String, value: String)] {
        var out: [(String, String)] = [
            (String(localized: "Time"), ForkRunMath.clockText(summary.seconds)),
            (String(localized: "Rounds"), "\(summary.rounds)"),
        ]
        if !summary.stations.isEmpty { out.append((String(localized: "Stations"), "\(summary.stations.count)")) }
        if let effort = summary.effortText { out.append((String(localized: "Effort"), effort)) }
        if let average = summary.averageBpm { out.append((String(localized: "Average"), "\(average) bpm")) }
        if let peak = summary.peakBpm { out.append((String(localized: "Peak"), "\(peak) bpm")) }
        if let drop = summary.averageRecoveryDrop {
            out.append((String(localized: "Recovery"), String(localized: "\(Int(drop.rounded())) bpm down")))
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.space5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: WorkoutSource.displaySport(summary.sport))
                        .font(StrandFont.rounded(28))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Session saved")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: NoopMetrics.space2),
                                    GridItem(.flexible(), spacing: NoopMetrics.space2)],
                          spacing: NoopMetrics.space2) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: tile.label)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                            Text(verbatim: tile.value)
                                .font(StrandFont.rounded(24, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(StrandPalette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(NoopMetrics.space4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NoopPanelSurface(cornerRadius: 20))
                    }
                }

                if !summary.stations.isEmpty {
                    VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                        Text("Stations")
                            .font(StrandFont.title2)
                            .foregroundStyle(StrandPalette.textPrimary)
                        VStack(spacing: 0) {
                            ForEach(summary.stations) { station in
                                HStack {
                                    Text("Station \(station.number)")
                                        .font(StrandFont.body)
                                        .foregroundStyle(StrandPalette.textPrimary)
                                    Spacer()
                                    Text(verbatim: stationText(station))
                                        .font(StrandFont.bodyNumber)
                                        .foregroundStyle(StrandPalette.textSecondary)
                                }
                                .padding(.horizontal, NoopMetrics.space4)
                                .frame(minHeight: 48)
                                .overlay(alignment: .bottom) {
                                    if station.number != summary.stations.count {
                                        Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                                            .padding(.leading, NoopMetrics.space4)
                                    }
                                }
                            }
                        }
                        .background(NoopPanelSurface(cornerRadius: 22))
                    }
                }

                VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                    Text("How was it done?")
                        .font(StrandFont.title2)
                        .foregroundStyle(StrandPalette.textPrimary)
                    chipRow(ForkSessionNote.companies, selection: $note.company)
                    chipRow(ForkSessionNote.kinds, selection: $note.kind)
                    Text("Optional. Tags stay on this iPhone and help compare like with like later.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                NoopButton("Done", kind: .primary, fullWidth: true) { onDone() }
            }
            .padding(NoopMetrics.space5)
        }
        .background(StrandPalette.surfaceBase.ignoresSafeArea())
        .onChangeCompat(of: note) { changed in
            ForkSessionNotes.save(changed, forStart: summary.startTs)
        }
    }

    private func stationText(_ station: ForkSessionSummary.Station) -> String {
        let time = ForkRunMath.clockText(station.seconds)
        return station.rounds == 1
            ? String(localized: "\(time) · 1 round")
            : String(localized: "\(time) · \(station.rounds) rounds")
    }

    /// One row of chips where at most one is chosen; tapping the chosen one clears it.
    private func chipRow(_ options: [(key: String, label: String)], selection: Binding<String?>) -> some View {
        HStack(spacing: NoopMetrics.space2) {
            ForEach(options, id: \.key) { option in
                let chosen = selection.wrappedValue == option.key
                Button {
                    selection.wrappedValue = chosen ? nil : option.key
                } label: {
                    Text(LocalizedStringKey(option.label))
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(chosen ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, NoopMetrics.space3)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(chosen ? StrandPalette.textPrimary : StrandPalette.surfaceOverlay))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}

/// Presents the summary when one is waiting. Sits in the app shell as a background, with its own
/// observation, so the shell itself is never redrawn by it.
struct ForkSessionSummaryHost: View {
    @ObservedObject private var presenter = ForkSessionSummaryPresenter.shared

    var body: some View {
        Color.clear
            .sheet(item: $presenter.pending) { summary in
                ForkSessionSummaryView(summary: summary) { presenter.pending = nil }
            }
    }
}

#if DEBUG
/// DEBUG-only sample states for the screenshot workflow. Sample numbers only.
enum ForkSessionSamples {
    static let working = ForkSessionDisplay(kind: .hiit, title: "Round 5", detail: "Station 2", value: "168",
                                            message: "Working",
                                            footnote: "Double-tap the strap to start a new station", isWorking: true)
    static let recovering = ForkSessionDisplay(kind: .hiit, title: "Round 5", detail: "Station 2", value: "141",
                                               message: "Recovering",
                                               footnote: "Double-tap the strap to start a new station", isWorking: false)
    static let calm = ForkSessionDisplay(kind: .calm, title: "Yoga", detail: nil, value: "68",
                                         message: "9 above your resting rate",
                                         footnote: "No targets, no buzzes", isWorking: false)
    static let summary = ForkSessionSummary(
        startTs: 1, sport: "HIIT", seconds: 3180, rounds: 14,
        stations: [.init(number: 1, seconds: 780, rounds: 4), .init(number: 2, seconds: 840, rounds: 4),
                   .init(number: 3, seconds: 720, rounds: 3), .init(number: 4, seconds: 840, rounds: 3)],
        averageBpm: 147, peakBpm: 181, averageRecoveryDrop: 31, effortText: "50.3")
}

struct ForkSessionCardDemo: View {
    let display: ForkSessionDisplay
    var body: some View {
        ScrollView { ForkSessionCard(display: display).padding(NoopMetrics.space5) }
    }
}
#endif
