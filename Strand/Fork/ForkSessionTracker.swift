//  ForkSessionTracker.swift
//  Personal fork only (not upstream).
//
//  What the fork adds around a live session that is not a coached run:
//
//    HIIT             no setup. Rounds are picked out of heart rate as the session goes
//                     (`EffortWaveEngine`, pure and unit tested), a double-tap on the strap marks a
//                     new station, and when the session ends a summary asks how it was done.
//    Yoga, Stretch    a quiet card: heart rate against resting, no targets and no buzzes.
//
//  Nothing here changes how a workout is scored or saved. The rounds, station marks and tags are
//  kept beside the saved workout, keyed by its start time, in `ForkSessionNotes`.

import Combine
import Foundation
import StrandAnalytics

// MARK: - Notes kept beside a saved workout

/// What the fork remembers about one session that the workout row has no place for.
struct ForkSessionNote: Codable, Equatable {
    var rounds: Int = 0
    /// Active elapsed seconds at each station mark.
    var stationMarks: [Double] = []
    /// How far heart rate came down after each round, averaged, when known.
    var averageRecoveryDrop: Double?
    /// "class", "partner" or "solo".
    var company: String?
    /// "cardio", "strength" or "mixed".
    var kind: String?

    static let companies: [(key: String, label: String)] = [
        ("class", "Class"), ("partner", "Partner"), ("solo", "On my own"),
    ]
    static let kinds: [(key: String, label: String)] = [
        ("cardio", "Cardio"), ("strength", "Strength"), ("mixed", "Mixed"),
    ]

    /// "Class · Mixed", or nil when nothing has been tagged.
    var tagLine: String? {
        let labels = [
            Self.companies.first { $0.key == company }?.label,
            Self.kinds.first { $0.key == kind }?.label,
        ].compactMap { $0 }
        return labels.isEmpty ? nil : labels.joined(separator: " · ")
    }
}

/// The notes store. On-device only, in the app's preferences. It is not part of a `.noopbak`
/// backup, so notes do not survive a restore onto a fresh install; the workouts themselves do.
enum ForkSessionNotes {
    private static let key = "fork.sessionNotes"
    private static let keep = 600

    private static func load() -> [String: ForkSessionNote] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let notes = try? JSONDecoder().decode([String: ForkSessionNote].self, from: data) else { return [:] }
        return notes
    }

    static func note(forStart startTs: Int) -> ForkSessionNote? {
        load()[String(startTs)]
    }

    static func save(_ note: ForkSessionNote, forStart startTs: Int) {
        var notes = load()
        notes[String(startTs)] = note
        if notes.count > keep {
            // Keys are start times, so the smallest are the oldest sessions.
            let oldest = notes.keys.compactMap(Int.init).sorted().prefix(notes.count - keep)
            for start in oldest { notes[String(start)] = nil }
        }
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - What the screens draw

/// The live card during a tracked session.
struct ForkSessionDisplay: Equatable {
    enum Kind: Equatable { case hiit, calm }
    var kind: Kind
    /// "Round 5", "Warming up", "Yoga".
    var title: String
    /// "Station 2", or nil when no station has been marked.
    var detail: String?
    /// The live heart rate, or "–".
    var value: String
    /// "Working", "Recovering", "9 above your resting rate".
    var message: String
    /// A quieter last line, such as how to mark a station.
    var footnote: String?
    /// True while heart rate is rising in a HIIT session.
    var isWorking: Bool
}

/// The summary shown when a HIIT session ends.
struct ForkSessionSummary: Identifiable, Equatable {
    struct Station: Equatable, Identifiable {
        let number: Int
        let seconds: Double
        let rounds: Int
        var id: Int { number }
    }

    /// The saved workout's start, unix seconds. Also the key its note is stored under.
    let startTs: Int
    var sport: String
    var seconds: Double
    var rounds: Int
    var stations: [Station]
    var averageBpm: Int?
    var peakBpm: Int?
    var averageRecoveryDrop: Double?
    /// Effort as the workout was saved with it, already formatted, when known.
    var effortText: String?

    var id: Int { startTs }
}

// MARK: - The tracker

@MainActor
final class ForkSessionTracker: ObservableObject {
    static let shared = ForkSessionTracker()

    /// The live card, or nil when the running session is not one the tracker follows.
    @Published private(set) var display: ForkSessionDisplay?

    private weak var model: AppModel?
    private var cancellables: Set<AnyCancellable> = []

    private var trackedStart: Date?
    private var sport = ""
    private var wave = EffortWaveEngine()
    private var stationMarks: [Double] = []
    private var lastSeen: AppModel.ActiveWorkout?
    private var holdsDoubleTap = false

    private static let hiitSports: Set<String> = ["HIIT"]
    private static let calmSports: Set<String> = ["Yoga", "Stretching"]

    private init() {}

    private var isHiit: Bool { Self.hiitSports.contains(sport) }
    private var isCalm: Bool { Self.calmSports.contains(sport) }

    /// Wire the tracker to the app model. Safe to call more than once.
    func attach(to model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        model.$activeWorkout
            .sink { [weak self] workout in self?.workoutChanged(workout) }
            .store(in: &cancellables)
        model.$bpm
            .sink { [weak self] bpm in self?.tick(bpm: bpm) }
            .store(in: &cancellables)
    }

    private func workoutChanged(_ workout: AppModel.ActiveWorkout?) {
        guard let workout else {
            if trackedStart != nil { finish() }
            return
        }
        if trackedStart != workout.start {
            trackedStart = workout.start
            sport = workout.sport
            wave = EffortWaveEngine()
            stationMarks = []
            display = nil
            claimDoubleTapIfNeeded()
        }
        // Keep the session's running totals without holding on to its sample list: a second
        // reference to that array would force a full copy of it on every new reading.
        var light = workout
        light.samples = []
        lastSeen = light
    }

    // MARK: Station marks

    /// During HIIT the strap's double-tap marks a new station. The gesture is only taken while it is
    /// free (a Lift Log session may already hold it) and is handed back the moment the session ends.
    private func claimDoubleTapIfNeeded() {
        guard isHiit, let model, model.strapDoubleTapOverride == nil else { return }
        model.strapDoubleTapOverride = { [weak self] in self?.markStation() }
        holdsDoubleTap = true
    }

    private func releaseDoubleTap() {
        if holdsDoubleTap { model?.strapDoubleTapOverride = nil }
        holdsDoubleTap = false
    }

    private func markStation() {
        guard isHiit, let model, let workout = model.activeWorkout, !workout.isPaused else { return }
        stationMarks.append(workout.elapsed())
        // One short buzz to confirm the mark, the same confirmation Lift Log gives a double-tap.
        model.buzz(loops: 1)
        refreshDisplay(bpm: model.bpm)
    }

    // MARK: One reading

    private func tick(bpm: Int?) {
        guard let model, trackedStart != nil, let workout = model.activeWorkout else { return }
        guard isHiit || isCalm else { return }
        if isHiit, !workout.isPaused, let bpm, bpm >= 30 {
            wave.ingest(bpm: Double(bpm), at: workout.elapsed())
        }
        refreshDisplay(bpm: bpm)
    }

    private func refreshDisplay(bpm: Int?) {
        guard let model else { return }
        let value = bpm.map(String.init) ?? "–"
        if isHiit {
            let title: String
            let message: String
            switch wave.phase {
            case .none:
                title = String(localized: "Warming up")
                message = String(localized: "Rounds start counting once your heart rate climbs")
            case .working:
                title = String(localized: "Round \(wave.currentRound)")
                message = String(localized: "Working")
            case .recovering:
                title = wave.currentRound > 0 ? String(localized: "Round \(wave.currentRound)") : String(localized: "Warming up")
                message = String(localized: "Recovering")
            }
            display = ForkSessionDisplay(
                kind: .hiit, title: title,
                detail: stationMarks.isEmpty ? nil : String(localized: "Station \(stationMarks.count + 1)"),
                value: value, message: message,
                footnote: holdsDoubleTap ? String(localized: "Double-tap the strap to start a new station") : nil,
                isWorking: wave.phase == .working)
        } else if isCalm {
            var message = String(localized: "No targets, no buzzes")
            if let bpm, let resting = model.repo.today?.restingHr, resting > 0 {
                let above = bpm - resting
                message = above > 0
                    ? String(localized: "\(above) above your resting rate")
                    : String(localized: "At your resting rate")
            }
            display = ForkSessionDisplay(kind: .calm, title: WorkoutSource.displaySport(sport), detail: nil,
                                         value: value, message: message,
                                         footnote: String(localized: "No targets, no buzzes"), isWorking: false)
        }
    }

    // MARK: End of session

    private func finish() {
        let start = trackedStart
        let workout = lastSeen
        let wasHiit = isHiit
        let rounds = wave.rounds
        let marks = stationMarks

        releaseDoubleTap()
        trackedStart = nil
        lastSeen = nil
        display = nil

        guard wasHiit, let start, let workout else { return }
        let seconds = workout.elapsed()
        let summary = Self.summary(startTs: Int(start.timeIntervalSince1970), sport: workout.sport,
                                   seconds: seconds, rounds: rounds, marks: marks,
                                   averageBpm: workout.avgHr > 0 ? workout.avgHr : nil,
                                   peakBpm: workout.peakHr > 0 ? workout.peakHr : nil)

        Task { [weak self] in
            // Give the in-exercise screen time to close, and the workout time to be saved.
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, let model = self.model else { return }
            // Only a session that was actually saved gets a summary and a note. One discarded as too
            // short leaves `lastWorkout` empty or pointing at something else.
            guard let saved = model.lastWorkout, abs(saved.startTs - summary.startTs) <= 1 else { return }
            var filled = summary
            // The saved row's own start is the key, so the note always lines up with the workout.
            filled = ForkSessionSummary(startTs: saved.startTs, sport: filled.sport, seconds: filled.seconds,
                                        rounds: filled.rounds, stations: filled.stations,
                                        averageBpm: filled.averageBpm, peakBpm: filled.peakBpm,
                                        averageRecoveryDrop: filled.averageRecoveryDrop,
                                        effortText: saved.strain.map { UnitFormatter.effortDisplay($0, scale: UnitPrefs.resolveEffortScale(UserDefaults.standard.string(forKey: UnitPrefs.effortScaleKey) ?? "")) })
            var note = ForkSessionNotes.note(forStart: saved.startTs) ?? ForkSessionNote()
            note.rounds = filled.rounds
            note.stationMarks = marks
            note.averageRecoveryDrop = filled.averageRecoveryDrop
            ForkSessionNotes.save(note, forStart: saved.startTs)
            ForkSessionSummaryPresenter.shared.pending = filled
        }
    }

    /// Builds the summary from what the session recorded. Pure, so it can be tested and previewed.
    static func summary(startTs: Int, sport: String, seconds: Double, rounds: [EffortWaveEngine.Round],
                        marks: [Double], averageBpm: Int?, peakBpm: Int?) -> ForkSessionSummary {
        let drops = rounds.compactMap(\.recoveryDrop)
        let averageDrop = drops.isEmpty ? nil : drops.reduce(0, +) / Double(drops.count)

        var stations: [ForkSessionSummary.Station] = []
        let cleanMarks = marks.filter { $0 > 0 && $0 < seconds }.sorted()
        if !cleanMarks.isEmpty {
            let edges = [0] + cleanMarks + [max(seconds, cleanMarks.last ?? 0)]
            for index in 0..<(edges.count - 1) {
                let from = edges[index], to = edges[index + 1]
                let inside = rounds.filter { $0.peakAt >= from && (index == edges.count - 2 ? $0.peakAt <= to : $0.peakAt < to) }
                stations.append(.init(number: index + 1, seconds: to - from, rounds: inside.count))
            }
        }
        return ForkSessionSummary(startTs: startTs, sport: sport, seconds: seconds, rounds: rounds.count,
                                  stations: stations, averageBpm: averageBpm, peakBpm: peakBpm,
                                  averageRecoveryDrop: averageDrop, effortText: nil)
    }
}

/// Holds the summary waiting to be shown. Kept apart from the tracker so the one view that presents
/// it is not redrawn by every heart-rate reading.
@MainActor
final class ForkSessionSummaryPresenter: ObservableObject {
    static let shared = ForkSessionSummaryPresenter()
    @Published var pending: ForkSessionSummary?
    private init() {}
}
