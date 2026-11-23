//  ForkRunCoach.swift
//  Personal fork only (not upstream).
//
//  The run coach: what a run is aiming for, and the object that watches a live session against it.
//
//  All of the judgement (when a reading counts, when to nudge, when to repeat) lives in
//  `TargetCoachEngine` and `IntervalClock` in the StrandAnalytics package, which are pure and unit
//  tested. This file only (1) turns live heart rate and pace into the engine's "below / inside /
//  above", (2) plays the engine's cues on the strap through `AppModel.buzz`, the same command every
//  other in-app cue uses, and (3) publishes what the live screen shows.

import Combine
import Foundation
import StrandAnalytics
import WhoopProtocol

// MARK: - What a run is aiming for

enum ForkRunMode: String, Codable, CaseIterable, Identifiable {
    /// Hold a heart-rate zone.
    case zone
    /// Hold a pace.
    case pace
    /// Reps at a pace, with recoveries.
    case intervals
    /// No target and no buzzes.
    case free

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zone: return String(localized: "Zone")
        case .pace: return String(localized: "Pace")
        case .intervals: return String(localized: "Intervals")
        case .free: return String(localized: "Free")
        }
    }

    var blurb: String {
        switch self {
        case .zone: return String(localized: "Hold a heart-rate zone. The strap buzzes if you drift out of it.")
        case .pace: return String(localized: "Hold a pace. Needs the phone on you for GPS, and pace lags a few seconds.")
        case .intervals: return String(localized: "Reps at a target pace with recoveries. A buzz starts and ends each rep.")
        case .free: return String(localized: "Just record. No target and no buzzes.")
        }
    }
}

struct ForkRunPlan: Codable, Equatable {
    var mode: ForkRunMode = .zone
    /// Target heart-rate zone, 1 to 5.
    var zone: Int = 2
    /// Target pace in seconds per kilometre, and how far either side still counts as on pace.
    var paceSecPerKm: Int = 360
    var paceToleranceSec: Int = 10
    var reps: Int = 6
    var workSec: Int = 120
    var restSec: Int = 90
    /// Whether the coach buzzes the strap. Off still shows the coach on screen.
    var buzz: Bool = true

    var intervalPlan: IntervalPlan { IntervalPlan(reps: reps, workSec: workSec, restSec: restSec) }

    private static let lastKey = "fork.runPlan.last"

    /// The plan last started, so the setup sheet opens where the wearer left it.
    static func loadLast() -> ForkRunPlan {
        guard let data = UserDefaults.standard.data(forKey: lastKey),
              let plan = try? JSONDecoder().decode(ForkRunPlan.self, from: data) else { return ForkRunPlan() }
        return plan.clamped
    }

    func saveAsLast() {
        if let data = try? JSONEncoder().encode(clamped) {
            UserDefaults.standard.set(data, forKey: Self.lastKey)
        }
    }

    /// Stored values pulled back into the ranges the setup sheet allows.
    var clamped: ForkRunPlan {
        var plan = self
        plan.zone = min(5, max(1, zone))
        plan.paceSecPerKm = min(900, max(150, paceSecPerKm))
        plan.paceToleranceSec = min(60, max(5, paceToleranceSec))
        plan.reps = min(40, max(1, reps))
        plan.workSec = min(3600, max(15, workSec))
        plan.restSec = min(1800, max(0, restSec))
        return plan
    }
}

/// Pure helpers: readings to positions, and numbers to text.
enum ForkRunMath {
    /// Heart rate against a zone. The top zone has no upper edge.
    static func position(bpm: Double, lower: Double, upper: Double, isTopZone: Bool) -> TargetCoachEngine.Position {
        if bpm < lower { return .below }
        if !isTopZone, bpm >= upper { return .above }
        return .inside
    }

    /// Pace against a target. A SLOWER pace is a larger number, and it means "do more", so it maps to
    /// `below`; a faster pace than asked maps to `above`.
    static func position(paceSecPerKm: Double, target: Int, tolerance: Int) -> TargetCoachEngine.Position {
        if paceSecPerKm > Double(target + tolerance) { return .below }
        if paceSecPerKm < Double(target - tolerance) { return .above }
        return .inside
    }

    /// "6:04" for 364 seconds per kilometre.
    static func paceText(_ secPerKm: Double) -> String {
        guard secPerKm.isFinite, secPerKm > 0 else { return "–" }
        let total = Int(secPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "12:40" for 760 seconds; "1:02:05" past the hour.
    static func clockText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - What the live screen shows

struct ForkRunCoachDisplay: Equatable {
    enum State: Equatable { case inTarget, below, above, waiting, resting, paused, done }

    /// "Zone 2", "Pace", "Rep 3 of 6".
    var title: String
    /// "124 to 137 bpm", "5:50 to 6:10 /km".
    var target: String
    /// The live number, already formatted: "131", "6:04".
    var value: String
    /// "bpm", "/km".
    var unit: String
    var state: State
    /// One plain line for the state: "In zone", "Below zone: pick it up", "Recovering, 0:45 left".
    var message: String
    /// "In target 12:40 of 18:05", or nil before any time has counted.
    var footnote: String?
}

// MARK: - The coach

/// Watches the live session against a `ForkRunPlan`. One shared instance, attached to the app model
/// once at launch; it coaches only while a workout it was given a plan for is running.
@MainActor
final class ForkRunCoach: ObservableObject {
    static let shared = ForkRunCoach()

    /// What the live screen draws, or nil when there is nothing to coach.
    @Published private(set) var display: ForkRunCoachDisplay?

    private(set) var plan: ForkRunPlan?
    /// True while a plan with a target is in force. The older zone buzz in `AppModel.coachZone`
    /// stands down while this is true, so the wearer never gets two sets of buzzes.
    var isCoaching: Bool { plan.map { $0.mode != .free } ?? false }

    private weak var model: AppModel?
    private var engine = TargetCoachEngine()
    private var cancellables: Set<AnyCancellable> = []
    private var lastPhaseKey: String?
    private var buzzingUntil = Date.distantPast

    private static let activeKey = "fork.runPlan.active"
    private struct ActivePlan: Codable {
        let plan: ForkRunPlan
        let startTs: Double
    }

    private init() {}

    /// Wire the coach to the app model. Safe to call more than once.
    func attach(to model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        // `@Published` hands the NEW value to the sink before the property itself changes, so both
        // sinks work from the value they are given, never from the property.
        model.$activeWorkout
            .sink { [weak self] workout in self?.workoutChanged(workout) }
            .store(in: &cancellables)
        model.$bpm
            .sink { [weak self] bpm in self?.tick(bpm: bpm) }
            .store(in: &cancellables)
    }

    /// Start coaching the workout that was just started. Call right after `AppModel.startWorkout`.
    func begin(_ plan: ForkRunPlan) {
        let plan = plan.clamped
        plan.saveAsLast()
        guard let start = model?.activeWorkout?.start else { return }
        adopt(plan)
        let record = ActivePlan(plan: plan, startTs: start.timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: Self.activeKey)
        }
    }

    private func adopt(_ plan: ForkRunPlan) {
        self.plan = plan
        engine = TargetCoachEngine()
        lastPhaseKey = nil
        display = nil
    }

    private func stop() {
        plan = nil
        display = nil
        lastPhaseKey = nil
        UserDefaults.standard.removeObject(forKey: Self.activeKey)
    }

    private func workoutChanged(_ workout: AppModel.ActiveWorkout?) {
        guard let workout else {
            if plan != nil { stop() }
            return
        }
        guard plan == nil else { return }
        // A session restored after the app was closed mid-run: pick its plan back up, but only if the
        // stored plan belongs to this very session.
        guard let data = UserDefaults.standard.data(forKey: Self.activeKey),
              let record = try? JSONDecoder().decode(ActivePlan.self, from: data),
              abs(record.startTs - workout.start.timeIntervalSince1970) < 2 else { return }
        adopt(record.plan.clamped)
    }

    // MARK: One reading

    private func tick(bpm: Int?) {
        guard let model, let plan, plan.mode != .free, let workout = model.activeWorkout else { return }
        let elapsed = workout.elapsed()

        if workout.isPaused {
            engine.breakContinuity()
            display = makeDisplay(plan: plan, model: model, bpm: bpm, position: nil, phase: nil,
                                  state: .paused, message: String(localized: "Paused"))
            return
        }

        var position: TargetCoachEngine.Position?
        var phase: IntervalPhase?

        switch plan.mode {
        case .free:
            return
        case .zone:
            if let bpm, bpm >= 30, let zone = model.profile.hrZoneSet.zones.first(where: { $0.number == plan.zone }) {
                position = ForkRunMath.position(bpm: Double(bpm), lower: zone.lower, upper: zone.upper,
                                                isTopZone: zone.number == 5)
            }
        case .pace:
            position = pacePosition(plan: plan, model: model)
        case .intervals:
            let current = IntervalClock.phase(for: plan.intervalPlan, activeElapsed: elapsed)
            phase = current
            announce(current, buzz: plan.buzz)
            if case .work = current { position = pacePosition(plan: plan, model: model) }
        }

        let cue = engine.ingest(position: position, at: elapsed)
        if let cue, plan.buzz { play(cue) }

        display = makeDisplay(plan: plan, model: model, bpm: bpm, position: position, phase: phase,
                              state: nil, message: nil)
    }

    private func pacePosition(plan: ForkRunPlan, model: AppModel) -> TargetCoachEngine.Position? {
        guard let pace = model.gpsRecorder.paceSecPerKm, pace.isFinite, pace > 0 else { return nil }
        return ForkRunMath.position(paceSecPerKm: pace, target: plan.paceSecPerKm,
                                    tolerance: plan.paceToleranceSec)
    }

    // MARK: Buzzes

    /// Mirrors `HapticClock`'s timing: a short buzz is the light one-loop pattern, a long buzz the
    /// heavier two-loop one, with a clear silence between buzzes.
    private static let shortMs = 200
    private static let longMs = 550
    private static let gapMs = 450

    private func play(_ cue: TargetCoachEngine.Cue) {
        switch cue {
        case .pushOn: play(LiveSessionHaptics.pulses(for: .push))         // two short
        case .easeOff: play(LiveSessionHaptics.pulses(for: .easeOff))     // three long
        case .backInTarget: play([HapticClock.Pulse(durationMs: Self.shortMs, gapMs: 0)])   // one short
        }
    }

    /// Buzz at the start of each rep (two long) and each recovery (one long). Once per phase.
    private func announce(_ phase: IntervalPhase, buzz: Bool) {
        let key: String
        let pulses: [HapticClock.Pulse]
        let long = HapticClock.Pulse(durationMs: Self.longMs, gapMs: Self.gapMs)
        let lastLong = HapticClock.Pulse(durationMs: Self.longMs, gapMs: 0)
        switch phase {
        case .work(let rep, _, _):
            key = "work\(rep)"; pulses = [long, lastLong]
        case .rest(let rep, _, _):
            key = "rest\(rep)"; pulses = [lastLong]
        case .done:
            key = "done"; pulses = [lastLong]
        }
        guard key != lastPhaseKey else { return }
        lastPhaseKey = key
        // A new phase makes any dwell in progress meaningless.
        engine.breakContinuity()
        if buzz { play(pulses) }
    }

    /// Walk a pulse list out through the strap. If a walk is still in flight the new one is dropped,
    /// never queued: a late nudge corrects nothing.
    private func play(_ pulses: [HapticClock.Pulse]) {
        let now = Date()
        guard now >= buzzingUntil, !pulses.isEmpty else { return }
        let totalMs = pulses.reduce(0) { $0 + $1.durationMs + $1.gapMs }
        buzzingUntil = now.addingTimeInterval(Double(totalMs) / 1000)
        Task { [weak self] in
            for pulse in pulses {
                guard let model = self?.model, model.activeWorkout != nil else { return }
                model.buzz(loops: pulse.isLong ? 2 : 1)
                try? await Task.sleep(nanoseconds: UInt64(pulse.durationMs + pulse.gapMs) * 1_000_000)
            }
        }
    }

    // MARK: Display

    private func makeDisplay(plan: ForkRunPlan, model: AppModel, bpm: Int?,
                             position: TargetCoachEngine.Position?, phase: IntervalPhase?,
                             state forcedState: ForkRunCoachDisplay.State?,
                             message forcedMessage: String?) -> ForkRunCoachDisplay {
        let paceLow = ForkRunMath.paceText(Double(plan.paceSecPerKm - plan.paceToleranceSec))
        let paceHigh = ForkRunMath.paceText(Double(plan.paceSecPerKm + plan.paceToleranceSec))
        let paceNow = model.gpsRecorder.paceSecPerKm.map(ForkRunMath.paceText) ?? "–"

        var title: String
        var target: String
        var value: String
        var unit: String
        let usesPace: Bool

        switch plan.mode {
        case .zone, .free:
            usesPace = false
            title = String(localized: "Zone \(plan.zone)")
            if let zone = model.profile.hrZoneSet.zones.first(where: { $0.number == plan.zone }) {
                target = zone.number == 5
                    ? String(localized: "\(Int(zone.lower.rounded())) bpm and above")
                    : String(localized: "\(Int(zone.lower.rounded())) to \(Int(zone.upper.rounded()) - 1) bpm")
            } else {
                target = "–"
            }
            value = bpm.map(String.init) ?? "–"
            unit = "bpm"
        case .pace:
            usesPace = true
            title = String(localized: "Pace")
            target = String(localized: "\(paceLow) to \(paceHigh) /km")
            value = paceNow
            unit = "/km"
        case .intervals:
            usesPace = true
            switch phase {
            case .work(let rep, let of, _): title = String(localized: "Rep \(rep) of \(of)")
            case .rest(let rep, let of, _): title = String(localized: "Recovery \(rep) of \(max(1, of - 1))")
            case .done, .none: title = String(localized: "Intervals")
            }
            target = String(localized: "\(paceLow) to \(paceHigh) /km")
            value = paceNow
            unit = "/km"
        }

        var state: ForkRunCoachDisplay.State
        var message: String
        if let forcedState, let forcedMessage {
            state = forcedState
            message = forcedMessage
        } else if case .rest(_, _, let left) = phase {
            state = .resting
            message = String(localized: "Recovering, \(ForkRunMath.clockText(Double(left))) left")
        } else if case .done = phase {
            state = .done
            message = String(localized: "All reps done")
        } else {
            switch position {
            case .inside:
                state = .inTarget
                message = usesPace ? String(localized: "On pace") : String(localized: "In zone")
            case .below:
                state = .below
                message = usesPace ? String(localized: "Too slow: pick it up") : String(localized: "Below zone: pick it up")
            case .above:
                state = .above
                message = usesPace ? String(localized: "Too fast: ease off") : String(localized: "Above zone: ease off")
            case .none:
                state = .waiting
                message = usesPace ? String(localized: "Waiting for GPS pace") : String(localized: "Waiting for heart rate")
            }
            if case .work(_, _, let left) = phase {
                message += String(localized: " · \(ForkRunMath.clockText(Double(left))) left")
            }
        }

        let counted = engine.secondsBelow + engine.secondsInside + engine.secondsAbove
        let footnote: String? = counted >= 1
            ? String(localized: "In target \(ForkRunMath.clockText(engine.secondsInside)) of \(ForkRunMath.clockText(counted))")
            : nil

        return ForkRunCoachDisplay(title: title, target: target, value: value, unit: unit,
                                   state: state, message: message, footnote: footnote)
    }
}
