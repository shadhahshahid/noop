//  ForkMoreMenu.swift
//  Personal fork only (not upstream).
//
//  The More tab as a short grouped menu with search. Ten rows at rest; each opens either one group
//  of Settings cards or a short list of the existing screens. Search looks across every destination
//  at once, including what sits inside each Settings group.
//
//  Every row pushes a `MoreDestination` value, so the tab's bound navigation path, pop-to-root on a
//  tab re-tap and the per-screen chrome registered in RootTabView all keep working unchanged.

#if os(iOS)
import SwiftUI
import StrandDesign

/// A second-level list in the More menu.
enum ForkMoreGroup: String, Hashable, CaseIterable {
    case strap, activities, health, alerts, backup, advanced

    var title: LocalizedStringKey {
        switch self {
        case .strap:      return "Strap"
        case .activities: return "Activities"
        case .health:     return "Health and insights"
        case .alerts:     return "Alerts and buzzes"
        case .backup:     return "Backup and data"
        case .advanced:   return "Advanced"
        }
    }
}

/// One row: where it goes, how it reads, and the words search should find it by.
struct ForkMoreItem: Identifiable {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    let route: MoreDestination
    var keywords: String = ""

    var id: String { title }

    func matches(_ query: String) -> Bool {
        let needle = query.lowercased()
        return title.lowercased().contains(needle)
            || (subtitle?.lowercased().contains(needle) ?? false)
            || keywords.contains(needle)
    }
}

enum ForkMoreIndex {
    /// The fork release this build belongs to. Shown under About so the wearer can tell which build
    /// is installed: fork builds keep upstream's version number, so the number alone cannot say.
    static let releaseName = "Data"

    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else {
            return "Your own build: \(releaseName)"
        }
        // The build number is what tells two fork builds of the same version apart.
        let build = (info?["CFBundleVersion"] as? String).map { " (\($0))" } ?? ""
        return "Version \(version)\(build), your own build: \(releaseName)"
    }

    /// The ten rows the More tab shows at rest.
    static var root: [ForkMoreItem] {
        [
            ForkMoreItem(title: "Profile", subtitle: "Age, weight, heart-rate zones",
                         symbol: "person.fill", route: .settingsGroup(.profile)),
            ForkMoreItem(title: "Strap", subtitle: "Connection, alarms, battery",
                         symbol: "dot.radiowaves.left.and.right", route: .group(.strap)),
            ForkMoreItem(title: "Activities", subtitle: "Live heart rate, lifting, intervals, breathing",
                         symbol: "figure.run", route: .group(.activities)),
            ForkMoreItem(title: "Health and insights", subtitle: "Stress, health, patterns in your data",
                         symbol: "heart.text.square.fill", route: .group(.health)),
            ForkMoreItem(title: "Look and feel", subtitle: "Theme, chart colours, language",
                         symbol: "paintbrush.fill", route: .settingsGroup(.look)),
            ForkMoreItem(title: "Alerts and buzzes", subtitle: "Automations, notifications, Siri",
                         symbol: "bell.fill", route: .group(.alerts)),
            ForkMoreItem(title: "Scores and units", subtitle: "Units, Effort scale, Charge baseline",
                         symbol: "ruler.fill", route: .settingsGroup(.scores)),
            ForkMoreItem(title: "Backup and data", subtitle: "Backups, Apple Health, exports",
                         symbol: "externaldrive.fill", route: .group(.backup)),
            ForkMoreItem(title: "Advanced", subtitle: "Features, experiments, diagnostics",
                         symbol: "wrench.and.screwdriver.fill", route: .group(.advanced)),
            ForkMoreItem(title: "About", subtitle: versionLine,
                         symbol: "info.circle.fill", route: .settingsGroup(.about)),
        ]
    }

    static func items(in group: ForkMoreGroup, coachEnabled: Bool) -> [ForkMoreItem] {
        switch group {
        case .strap:
            return [
                ForkMoreItem(title: "Strap settings", subtitle: "Connection, strap log, sync, HRV capture",
                             symbol: "dot.radiowaves.left.and.right", route: .settingsGroup(.strap),
                             keywords: "re-scan rescan disconnect rename strap name log continuous hrv window keep screen on while syncing bluetooth pair"),
                ForkMoreItem(title: "Alarms", subtitle: "Wake with a buzz on the strap",
                             symbol: "alarm.fill", route: .alarms, keywords: "wake smart alarm buzz morning"),
                ForkMoreItem(title: "Power saving", subtitle: "Make the strap battery last longer",
                             symbol: "battery.25", route: .powerSaving, keywords: "battery charge drain"),
                ForkMoreItem(title: "NOOP Limitations", subtitle: "What NOOP can read from each strap",
                             symbol: "list.bullet.rectangle", route: .noopLimitations, keywords: "capability 4.0 5.0 mg supported"),
            ]
        case .activities:
            return [
                ForkMoreItem(title: "Live", subtitle: "Heart rate right now",
                             symbol: "waveform.path.ecg", route: .live, keywords: "bpm heart rate zones real time"),
                ForkMoreItem(title: "Workouts", subtitle: "Every session you have recorded",
                             symbol: "figure.run", route: .workouts, keywords: "history sessions run hiit yoga stretch export gpx fit"),
                ForkMoreItem(title: "Lift Log", subtitle: "Programs, sets and rest buzzes",
                             symbol: "dumbbell.fill", route: .liftLog, keywords: "strength gym weights lifting hevy sets reps"),
                ForkMoreItem(title: "Intervals", subtitle: "Work and rest timer with buzzes",
                             symbol: "timer", route: .intervals, keywords: "interval timer tabata rounds"),
                ForkMoreItem(title: "Breathe", subtitle: "Guided breathing",
                             symbol: "wind", route: .breathe, keywords: "breathing calm relax"),
            ]
        case .health:
            var rows = [
                ForkMoreItem(title: "Health", subtitle: "Vitals and early warnings",
                             symbol: "heart.text.square.fill", route: .health, keywords: "vitals spo2 skin temperature respiratory illness fitness age vo2"),
                ForkMoreItem(title: "Stress", subtitle: "Stress through the day",
                             symbol: "bolt.heart.fill", route: .stress),
                ForkMoreItem(title: "Lab Book", subtitle: "Your own experiments",
                             symbol: "books.vertical.fill", route: .labBook, keywords: "experiment journal test"),
                ForkMoreItem(title: "Rhythm", subtitle: "Beat-to-beat regularity (experimental)",
                             symbol: "waveform.path", route: .rhythm, keywords: "heart rhythm irregular"),
                ForkMoreItem(title: "What Moves You", subtitle: "What raises and lowers your scores",
                             symbol: "wand.and.sparkles", route: .insightsHub, keywords: "patterns correlation behaviour"),
                ForkMoreItem(title: "Intelligence", subtitle: "Training load and readiness",
                             symbol: "brain.head.profile", route: .intelligence, keywords: "load readiness acwr"),
                ForkMoreItem(title: "Insights", subtitle: "Journal and what it shows",
                             symbol: "lightbulb.fill", route: .insights, keywords: "journal habits"),
                ForkMoreItem(title: "Explore", subtitle: "Any metric over time",
                             symbol: "square.grid.2x2.fill", route: .explore, keywords: "metric explorer chart history"),
                ForkMoreItem(title: "Compare", subtitle: "Two periods side by side",
                             symbol: "rectangle.split.2x1.fill", route: .compare),
            ]
            if coachEnabled {
                rows.append(ForkMoreItem(title: "Coach", subtitle: "AI coach (needs your own key)",
                                         symbol: "sparkles", route: .coach, keywords: "ai assistant chat"))
            }
            return rows
        case .alerts:
            return [
                ForkMoreItem(title: "Automations", subtitle: "Zone buzzes and other wrist alerts",
                             symbol: "wand.and.stars", route: .automations, keywords: "zone coach buzz haptic strain target vibrate"),
                ForkMoreItem(title: "Live notifications", subtitle: "Lock-screen activity during sessions",
                             symbol: "bell.badge.fill", route: .settingsGroup(.alerts), keywords: "live activity lock screen dynamic island"),
                ForkMoreItem(title: "Siri & Shortcuts", subtitle: "Voice and Shortcuts actions",
                             symbol: "mic.fill", route: .siriShortcuts, keywords: "siri voice shortcut"),
            ]
        case .backup:
            return [
                ForkMoreItem(title: "Backup & Sync", subtitle: "Save a backup to a folder you choose",
                             symbol: "externaldrive.fill.badge.icloud", route: .backupSync, keywords: "icloud backup now restore noopbak folder"),
                ForkMoreItem(title: "Backup and restore", subtitle: "Export or restore everything",
                             symbol: "arrow.triangle.2.circlepath", route: .settingsGroup(.backup), keywords: "export import restore backup"),
                ForkMoreItem(title: "Apple Health", subtitle: "Read from and write to Health",
                             symbol: "heart.fill", route: .appleHealth, keywords: "healthkit import export"),
                ForkMoreItem(title: "Data Sources", subtitle: "Where each number comes from",
                             symbol: "externaldrive.fill", route: .dataSources, keywords: "source provenance import csv"),
                ForkMoreItem(title: "Your Data, Fused", subtitle: "One record across sources",
                             symbol: "square.stack.3d.up.fill", route: .fusedRecord),
                ForkMoreItem(title: "Mi Band", subtitle: "Import from a Xiaomi band",
                             symbol: "figure.walk.motion", route: .miBand, keywords: "xiaomi"),
                ForkMoreItem(title: "Shortcuts Export", subtitle: "Send data out through Shortcuts",
                             symbol: "square.and.arrow.up.fill", route: .shortcutsExport, keywords: "export shortcut"),
            ]
        case .advanced:
            return [
                ForkMoreItem(title: "Features and experiments", subtitle: "Optional features and prototypes",
                             symbol: "flask.fill", route: .settingsGroup(.advanced),
                             keywords: "hydration auto-detect workouts journal reminder keep screen on liquid today live sessions sleep staging raw sensor export diagnostics experimental"),
                ForkMoreItem(title: "Test Centre", subtitle: "Diagnostics and bug reports",
                             symbol: "stethoscope", route: .testCentre, keywords: "diagnostics debug log report"),
            ]
        }
    }

    /// Search keywords for the rows that open a Settings group straight from the root.
    private static let rootKeywords: [String: String] = [
        "Profile": "date of birth age sex weight height waist max heart rate custom hr zones day starts step calibration photo avatar background",
        "Look and feel": "appearance language clock theme preset dark light chart colours sleep chart accent colour hide bar trend charts ai coach",
        "Scores and units": "units metric imperial kilometres miles temperature effort scale recovery recalibrate charge baseline streak",
        "About": "version what's new how noop works scores storage check for updates source github",
    ]

    /// Every destination, flat, for search. Group rows themselves are left out: search should land on
    /// the screen, not on another list.
    static func search(_ query: String, coachEnabled: Bool) -> [ForkMoreItem] {
        var all: [ForkMoreItem] = root.compactMap { item in
            guard let keywords = rootKeywords[item.title] else { return nil }
            var copy = item
            copy.keywords = keywords
            return copy
        }
        for group in ForkMoreGroup.allCases {
            all.append(contentsOf: items(in: group, coachEnabled: coachEnabled))
        }
        return all.filter { $0.matches(query) }
    }
}

// MARK: - Views

/// The More tab's content: a search field over the ten root rows, or over the matches while typing.
struct ForkMoreMenu: View {
    let coachEnabled: Bool
    @State private var query = ""
    @FocusState private var searching: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            searchField
            if trimmedQuery.isEmpty {
                ForkMoreList(items: ForkMoreIndex.root)
            } else {
                let hits = ForkMoreIndex.search(trimmedQuery, coachEnabled: coachEnabled)
                if hits.isEmpty {
                    Text("Nothing matches that. Try a shorter word.")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                } else {
                    ForkMoreList(items: hits)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: NoopMetrics.space2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
            TextField("Search settings and screens", text: $query)
                .font(StrandFont.body)
                .foregroundStyle(StrandPalette.textPrimary)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
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
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(StrandPalette.surfaceOverlay)
        )
    }
}

/// A rimless card of rows separated by hairlines.
struct ForkMoreList: View {
    let items: [ForkMoreItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                NavigationLink(value: item.route) {
                    row(item, isLast: index == items.count - 1)
                }
                .buttonStyle(.plain)
            }
        }
        .background(NoopPanelSurface(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func row(_ item: ForkMoreItem, isLast: Bool) -> some View {
        HStack(spacing: NoopMetrics.space3) {
            Image(systemName: item.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(StrandPalette.surfaceOverlay)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(item.title))
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                if let subtitle = item.subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: NoopMetrics.space2)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(.horizontal, NoopMetrics.space4)
        .frame(minHeight: 60)
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// One second-level list (Strap, Activities, …), pushed from the root menu.
struct ForkMoreGroupPage: View {
    let group: ForkMoreGroup
    @AppStorage("noop.coachEnabled") private var coachEnabled = true

    var body: some View {
        ScreenScaffold(title: group.title, topBackground: liquidScaffoldSky()) {
            ForkMoreList(items: ForkMoreIndex.items(in: group, coachEnabled: coachEnabled))
        }
    }
}
#endif
