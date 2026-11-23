//  ForkTrainingView.swift
//  Personal fork only (not upstream).
//
//  One screen for "how is my training going": sessions by type, this week's load against the usual,
//  how the time splits between easy, steady and hard, a marker per kind of session, and the
//  stretch streak. The grouping and counting is `TrainingOverview` in StrandAnalytics (pure, unit
//  tested); the zone split is the app's own `WorkoutZones.summary`. No new score is invented here.

#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

struct ForkTrainingView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    /// Sessions from the last six weeks or so, or nil until the first read finishes.
    @State private var rows: [WorkoutRow]?

    private static let weekCount = 6

    var body: some View {
        ScreenScaffold(title: "Training", topBackground: liquidScaffoldSky()) {
            if let rows {
                if rows.isEmpty {
                    Text("No sessions in the last six weeks. Start one from the Train tab and this fills in.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .padding(NoopMetrics.space4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NoopPanelSurface(cornerRadius: 22))
                } else {
                    ForkTrainingContent(model: ForkTrainingModel(rows: rows, now: Date(), calendar: .current,
                                                                 effortScale: effortScale))
                }
            }
        }
        .task(id: repo.refreshSeq) {
            let cutoff = Int(Date().timeIntervalSince1970) - (Self.weekCount * 7 + 7) * 86_400
            rows = await repo.workoutRows(days: Self.weekCount * 7 + 7).filter { $0.startTs >= cutoff }
        }
    }
}

/// Everything the Training screen draws, worked out once from the sessions. A plain value, so the
/// screenshot workflow can build one from sample sessions.
struct ForkTrainingModel {
    struct TypeCount: Identifiable {
        let sport: String
        let count: Int
        var id: String { sport }
    }

    struct Marker: Identifiable {
        let title: String
        let value: String
        let detail: String
        var id: String { title }
    }

    let types: [TypeCount]
    let weeks: [TrainingOverview.Week]
    /// This week's load on the wearer's Effort scale, as text.
    let loadText: String
    let changeText: String
    let changeIsHigh: Bool
    /// Share of zone time that was easy (zones 1 and 2), steady (3) and hard (4 and 5); nil when no
    /// session carried zone data.
    let mix: (easy: Double, steady: Double, hard: Double)?
    let markers: [Marker]
    let stretch: TrainingOverview.Streak

    init(rows: [WorkoutRow], now: Date, calendar: Calendar, effortScale: EffortScale,
         note: (Int) -> ForkSessionNote? = ForkSessionNotes.note(forStart:)) {
        func seconds(_ row: WorkoutRow) -> Double { row.durationS ?? Double(max(0, row.endTs - row.startTs)) }
        func start(_ row: WorkoutRow) -> Date { Date(timeIntervalSince1970: TimeInterval(row.startTs)) }

        let counts = Dictionary(grouping: rows, by: \.sport).map { TypeCount(sport: $0.key, count: $0.value.count) }
        types = Array(counts.sorted { $0.count != $1.count ? $0.count > $1.count : $0.sport < $1.sport }.prefix(4))

        let sessions = rows.map { TrainingOverview.Session(start: start($0), load: $0.strain, seconds: seconds($0)) }
        weeks = TrainingOverview.weeks(sessions, now: now, count: 6, calendar: calendar)
        loadText = UnitFormatter.effortDisplay(weeks.last?.load ?? 0, scale: effortScale)
        if (weeks.last?.sessions ?? 0) == 0 {
            // A week with nothing in it yet is not "100% below": it has simply not started.
            changeText = String(localized: "No sessions yet this week")
            changeIsHigh = false
        } else if let change = TrainingOverview.changeVersusUsual(weeks) {
            let percent = Int((abs(change) * 100).rounded())
            if percent < 5 {
                changeText = String(localized: "About a usual week")
                changeIsHigh = false
            } else if change > 0 {
                changeText = String(localized: "\(percent)% above a usual week")
                changeIsHigh = change >= 0.3
            } else {
                changeText = String(localized: "\(percent)% below a usual week, so far")
                changeIsHigh = false
            }
        } else {
            changeText = String(localized: "Your usual shows after a second week")
            changeIsHigh = false
        }

        if let zones = WorkoutZones.summary(from: rows), zones.totalMinutes > 0 {
            let total = zones.totalMinutes
            mix = ((zones.minutes[0] + zones.minutes[1]) / total, zones.minutes[2] / total,
                   (zones.minutes[3] + zones.minutes[4]) / total)
        } else {
            mix = nil
        }

        var found: [Marker] = []
        // HIIT: how far heart rate comes down between rounds, from sessions this build tracked.
        let drops = rows.filter { $0.sport == "HIIT" }.compactMap { note($0.startTs)?.averageRecoveryDrop }
        if !drops.isEmpty {
            let average = Int((drops.reduce(0, +) / Double(drops.count)).rounded())
            found.append(Marker(title: String(localized: "From your HIIT"),
                                value: String(localized: "Recovery between rounds: \(average) bpm"),
                                detail: drops.count == 1 ? String(localized: "From 1 session")
                                                         : String(localized: "From \(drops.count) sessions")))
        }
        // Runs: average pace and the heart rate it cost, so the pair can be watched over time.
        let runs = rows.filter { $0.sport == "Running" && ($0.distanceM ?? 0) >= 500 && seconds($0) > 0 }
        if !runs.isEmpty {
            let metres = runs.compactMap(\.distanceM).reduce(0, +)
            let time = runs.map(seconds).reduce(0, +)
            let pace = ForkRunMath.paceText(time / (metres / 1000))
            let rates = runs.compactMap(\.avgHr)
            let rate = rates.isEmpty ? nil : Int((Double(rates.reduce(0, +)) / Double(rates.count)).rounded())
            found.append(Marker(title: String(localized: "From your runs"),
                                value: rate.map { String(localized: "\(pace) /km at \($0) bpm") }
                                    ?? String(localized: "\(pace) /km"),
                                detail: runs.count == 1 ? String(localized: "From 1 run with GPS")
                                                        : String(localized: "From \(runs.count) runs with GPS")))
        }
        markers = found

        stretch = TrainingOverview.streak(sessionStarts: rows.filter { $0.sport == "Stretching" }.map(start),
                                          now: now, window: 28, calendar: calendar)
    }
}

struct ForkTrainingContent: View {
    let model: ForkTrainingModel

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text("Last 6 weeks")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
            typeTiles
            loadCard
            if let mix = model.mix { mixCard(mix) }
            markersCard
            stretchCard
        }
    }

    private var typeTiles: some View {
        HStack(spacing: NoopMetrics.space2) {
            ForEach(model.types) { type in
                VStack(spacing: 2) {
                    Text(verbatim: "\(type.count)")
                        .font(StrandFont.rounded(22, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(verbatim: WorkoutSource.displaySport(type.sport))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.vertical, NoopMetrics.space3)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .background(NoopPanelSurface(cornerRadius: 18))
            }
        }
    }

    private var loadCard: some View {
        let peak = max(model.weeks.map(\.load).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: NoopMetrics.space4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Load this week so far")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(verbatim: model.loadText)
                    .font(StrandFont.rounded(34, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: model.changeText)
                    .font(StrandFont.caption)
                    .foregroundStyle(model.changeIsHigh ? StrandPalette.statusWarning : StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: NoopMetrics.space2)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(model.weeks.enumerated()), id: \.offset) { index, week in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(index == model.weeks.count - 1 ? StrandPalette.textPrimary : StrandPalette.textTertiary.opacity(0.4))
                        .frame(width: 14, height: max(4, 64 * week.load / peak))
                }
            }
            .frame(height: 64, alignment: .bottom)
            .accessibilityHidden(true)
        }
        .padding(NoopMetrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func mixCard(_ mix: (easy: Double, steady: Double, hard: Double)) -> some View {
        let parts: [(label: String, zones: String, share: Double, color: Color)] = [
            (String(localized: "easy"), String(localized: "Zones 1 to 2"), mix.easy, StrandPalette.textTertiary),
            (String(localized: "steady"), String(localized: "Zone 3"), mix.steady, StrandPalette.textSecondary),
            (String(localized: "hard"), String(localized: "Zones 4 to 5"), mix.hard, StrandPalette.textPrimary),
        ]
        return VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text("Intensity mix, by time")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
            GeometryReader { geometry in
                HStack(spacing: 3) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(part.color)
                            .frame(width: max(0, (geometry.size.width - 6) * part.share))
                    }
                }
            }
            .frame(height: 14)
            .accessibilityHidden(true)
            HStack(alignment: .top, spacing: NoopMetrics.space2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "\(Int((part.share * 100).rounded()))% \(part.label)")
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(verbatim: part.zones)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(NoopMetrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: 24))
    }

    @ViewBuilder private var markersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Markers to watch")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.bottom, NoopMetrics.space2)
            if model.markers.isEmpty {
                Text("Markers appear after a HIIT session tracked by this build, or a run recorded with GPS.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(model.markers.enumerated()), id: \.element.id) { index, marker in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: marker.title)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                        Text(verbatim: marker.value)
                            .font(StrandFont.body.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Text(verbatim: marker.detail)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    .padding(.vertical, NoopMetrics.space3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(StrandPalette.hairline).frame(height: 1) }
                    }
                }
            }
        }
        .padding(NoopMetrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: 24))
    }

    private var stretchCard: some View {
        HStack(alignment: .center, spacing: NoopMetrics.space4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Morning stretch")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(model.stretch.current == 0 ? "No streak yet"
                     : (model.stretch.current == 1 ? "1-day streak" : "\(model.stretch.current)-day streak"))
                    .font(StrandFont.rounded(22, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("\(model.stretch.daysDone) of the last \(model.stretch.days.count) days")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer(minLength: NoopMetrics.space2)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(12), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(model.stretch.days.enumerated()), id: \.offset) { _, done in
                    Circle()
                        .fill(done ? StrandPalette.textPrimary : StrandPalette.textTertiary.opacity(0.3))
                        .frame(width: 12, height: 12)
                }
            }
            .fixedSize()
            .accessibilityHidden(true)
        }
        .padding(NoopMetrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoopPanelSurface(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}
#endif
