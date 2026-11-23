//  ForkDataView.swift
//  Personal fork only (not upstream).
//
//  The Data tab: four headline numbers, a search across every metric, and doors into the analysis
//  screens the app already has. It replaces Trends as the tab's first screen; Trends is one of the
//  doors and is unchanged. Every number here is read from the same daily rows and series the
//  existing screens use.

#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

struct ForkDataView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.effortScaleKey) private var effortScaleRaw = EffortScale.hundred.rawValue
    private var effortScale: EffortScale { UnitPrefs.resolveEffortScale(effortScaleRaw) }

    @State private var query = ""
    /// Sleep score by day, oldest first. It lives in a series, not in the daily rows.
    @State private var sleepByDay: [(day: String, value: Double)] = []

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScreenScaffold(title: "Data",
                       onRefresh: { await repo.refresh() },
                       topBackground: liquidScaffoldSky()) {
            searchField
            if trimmedQuery.isEmpty {
                headlineGrid
                doors
            } else {
                searchResults
            }
        }
        .task(id: repo.refreshSeq) {
            sleepByDay = await repo.exploreSeries(key: HeroRingMetric.rest, source: "my-whoop", days: 30)
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: NoopMetrics.space2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
            TextField("Search every metric", text: $query)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, NoopMetrics.space4)
        .frame(minHeight: 46)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(StrandPalette.surfaceOverlay))
    }

    @ViewBuilder private var searchResults: some View {
        let needle = trimmedQuery.lowercased()
        let hits = MetricCatalog.all.filter { $0.title.lowercased().contains(needle) }
        if hits.isEmpty {
            Text("No metric matches that. Try a shorter word.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.horizontal, 4)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(hits.prefix(30).enumerated()), id: \.element.id) { index, metric in
                    NavigationLink(value: TabRoute.metricSourced(key: metric.key, source: metric.source)) {
                        rowLabel(title: metric.title, subtitle: metric.sourceLabel, symbol: metric.icon,
                                 isLast: index == min(hits.count, 30) - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(NoopPanelSurface(cornerRadius: 22))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    // MARK: Headline numbers

    private struct Headline: Identifiable {
        let id: String            // the metric key the tile opens
        let label: LocalizedStringKey
        let value: String
        let caption: String
    }

    /// The newest value of a series and the average of up to seven days before it.
    private static func latestAndUsual(_ values: [Double]) -> (latest: Double, usual: Double?)? {
        guard let latest = values.last else { return nil }
        let earlier = values.dropLast().suffix(7)
        return (latest, earlier.isEmpty ? nil : earlier.reduce(0, +) / Double(earlier.count))
    }

    private var headlines: [Headline] {
        let days = repo.days.sorted { $0.day < $1.day }
        func tile(_ key: String, _ label: LocalizedStringKey, _ values: [Double], _ format: (Double) -> String) -> Headline {
            guard let pair = Self.latestAndUsual(values) else {
                return Headline(id: key, label: label, value: "–", caption: String(localized: "No data yet"))
            }
            let caption = pair.usual.map { String(localized: "7-day average \(format($0))") }
                ?? String(localized: "First reading")
            return Headline(id: key, label: label, value: format(pair.latest), caption: caption)
        }
        let whole: (Double) -> String = { String(Int($0.rounded())) }
        return [
            tile(HeroRingMetric.charge, "Charge", days.compactMap(\.recovery), whole),
            tile(HeroRingMetric.effort, "Effort", days.compactMap(\.strain),
                 { UnitFormatter.effortDisplay($0, scale: effortScale) }),
            tile(HeroRingMetric.rest, "Sleep", sleepByDay.map(\.value), whole),
            tile("hrv", "HRV", days.compactMap(\.avgHrv), { String(localized: "\(Int($0.rounded())) ms") }),
        ]
    }

    private var headlineGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: NoopMetrics.space2),
                            GridItem(.flexible(), spacing: NoopMetrics.space2)],
                  spacing: NoopMetrics.space2) {
            ForEach(headlines) { headline in
                NavigationLink(value: TabRoute.metric(headline.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline.label)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                        Text(verbatim: headline.value)
                            .font(StrandFont.rounded(30, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(StrandPalette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(verbatim: headline.caption)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(NoopMetrics.space4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NoopPanelSurface(cornerRadius: 22))
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Doors

    private var doors: some View {
        VStack(spacing: 0) {
            door("Training", "Load, intensity, streaks and fitness markers", "figure.strengthtraining.traditional", isLast: false) {
                ForkTrainingView()
            }
            door("Trends", "Your week and month in review", "chart.line.uptrend.xyaxis", isLast: false) {
                TrendsView()
            }
            NavigationLink(value: TabRoute.metricExplorer) {
                rowLabel(title: String(localized: "Every metric"), subtitle: String(localized: "Any number over time"),
                         symbol: "square.grid.2x2.fill", isLast: false)
            }
            .buttonStyle(.plain)
            door("Compare", "Two or more metrics on one chart", "rectangle.split.2x1.fill", isLast: false) {
                CompareView()
            }
            door("Patterns", "What raises and lowers your scores", "wand.and.sparkles", isLast: false) {
                InsightsHubView()
            }
            NavigationLink(value: TabRoute.health) {
                rowLabel(title: String(localized: "Health"), subtitle: String(localized: "Vitals and early warnings"),
                         symbol: "heart.text.square.fill", isLast: false)
            }
            .buttonStyle(.plain)
            NavigationLink(value: TabRoute.stress) {
                rowLabel(title: String(localized: "Stress"), subtitle: String(localized: "Stress through the day"),
                         symbol: "bolt.heart.fill", isLast: true)
            }
            .buttonStyle(.plain)
        }
        .background(NoopPanelSurface(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func door<Destination: View>(_ title: String, _ subtitle: String, _ symbol: String, isLast: Bool,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
        } label: {
            rowLabel(title: String(localized: String.LocalizationValue(title)),
                     subtitle: String(localized: String.LocalizationValue(subtitle)), symbol: symbol, isLast: isLast)
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(title: String, subtitle: String, symbol: String, isLast: Bool) -> some View {
        HStack(spacing: NoopMetrics.space3) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceOverlay))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: subtitle).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    .lineLimit(1)
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
}
#endif
