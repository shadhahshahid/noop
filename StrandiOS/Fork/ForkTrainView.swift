//  ForkTrainView.swift
//  Personal fork only (not upstream).
//
//  The Train tab: start a session, see the last few, and reach the tools around training. It
//  replaces the full Workouts list as the tab's first screen; that list is one tap away under
//  "All sessions" and is unchanged.

#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

struct ForkTrainView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    /// The newest sessions, newest first. Nil until the first read finishes.
    @State private var recent: [WorkoutRow]?

    private static let recentCount = 5

    var body: some View {
        ScreenScaffold(title: "Train",
                       onRefresh: { await repo.refresh() },
                       topBackground: liquidScaffoldSky()) {
            // The card for a session already in progress; draws nothing otherwise.
            ActiveWorkoutIndicatorSection(showStart: false)
            ForkQuickStarts()
            recentSection
            toolsSection
        }
        .task(id: repo.refreshSeq) {
            let rows = await repo.workoutRows(days: 90)
            recent = Array(rows.sorted { $0.startTs > $1.startTs }.prefix(Self.recentCount))
        }
    }

    // MARK: Recent sessions

    @ViewBuilder private var recentSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .font(StrandFont.title2)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                NavigationLink(value: TabRoute.workouts) {
                    Text("All sessions")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let recent {
                if recent.isEmpty {
                    Text("No sessions yet. Start one above and it will show here.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .padding(NoopMetrics.space4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NoopPanelSurface(cornerRadius: 22))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.startTs) { index, row in
                            NavigationLink {
                                WorkoutDetailView(row: row)
                            } label: {
                                sessionRow(row, isLast: index == recent.count - 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(NoopPanelSurface(cornerRadius: 22))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }

    private func sessionRow(_ row: WorkoutRow, isLast: Bool) -> some View {
        HStack(spacing: NoopMetrics.space3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: WorkoutSource.displaySport(row.sport))
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .lineLimit(1)
                Text(verbatim: Self.whenText(row))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: NoopMetrics.space2)
            if let strain = row.strain {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: UnitFormatter.effortDisplay(strain, scale: effortScale))
                        .font(StrandFont.rounded(19, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Effort")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.horizontal, NoopMetrics.space4)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(StrandPalette.hairline)
                    .frame(height: 1)
                    .padding(.leading, NoopMetrics.space4)
            }
        }
    }

    /// "Today, 53 min" / "Sat 21 Nov, 31 min".
    private static func whenText(_ row: WorkoutRow) -> String {
        let start = Date(timeIntervalSince1970: TimeInterval(row.startTs))
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(start) {
            day = String(localized: "Today")
        } else if calendar.isDateInYesterday(start) {
            day = String(localized: "Yesterday")
        } else {
            day = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        let seconds = row.durationS ?? Double(max(0, row.endTs - row.startTs))
        let minutes = max(1, Int((seconds / 60).rounded()))
        return String(localized: "\(day), \(minutes) min")
    }

    // MARK: Tools

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            Text("Tools")
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            VStack(spacing: 0) {
                toolRow("Interval timer", "Work and rest with buzzes", "timer", isLast: false) { IntervalTimerView() }
                toolRow("Lift Log", "Programs, sets and rest buzzes", "dumbbell.fill", isLast: false) { LiftLogView() }
                toolRow("Breathe", "Guided breathing", "wind", isLast: true) { BreathingView() }
            }
            .background(NoopPanelSurface(cornerRadius: 22))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func toolRow<Destination: View>(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey,
                                            _ symbol: String, isLast: Bool,
                                            @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
        } label: {
            HStack(spacing: NoopMetrics.space3) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceOverlay))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                    Text(subtitle).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                }
                Spacer(minLength: NoopMetrics.space2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.horizontal, NoopMetrics.space4)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle()
                        .fill(StrandPalette.hairline)
                        .frame(height: 1)
                        .padding(.leading, NoopMetrics.space4 + 34 + NoopMetrics.space3)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
