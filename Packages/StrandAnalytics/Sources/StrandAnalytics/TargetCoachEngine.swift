import Foundation

// Personal fork only (not upstream, no Android twin): the logic behind the run coach.
//
// Two pure value types, with no clock, no strap and no user interface of their own:
//
//   TargetCoachEngine  decides WHEN to nudge someone who is holding a target (a heart-rate zone or a
//                      pace). It is fed one reading at a time, already reduced to "below the target,
//                      inside it, or above it", and answers with at most one cue.
//   IntervalClock      says which rep of a work-and-rest session a given moment falls in.
//
// Both take the session's ACTIVE elapsed time in seconds (paused time excluded), supplied by the
// caller, so every rule below can be tested exactly, with no waiting and no hardware.

/// Decides when to cue a wearer who is holding a target.
///
/// The rules, in the order they apply:
///  1. A reading must hold a new position for `dwellSec` in a row before it counts. One stray
///     reading across a boundary changes nothing.
///  2. On settling below the target: `pushOn`. On settling above it: `easeOff`.
///  3. While still out of the target, the same cue repeats every `reminderSec`.
///  4. On settling back inside after an excursion that was cued: `backInTarget`, once. In the target
///     the engine is otherwise silent.
///  5. `pushOn` is held back for the first `warmupSec` of the session, so a warm-up is not nagged.
///     `easeOff` is never held back.
///  6. A gap in readings longer than `maxGapSec` (signal lost, session paused) breaks any dwell in
///     progress, and that gap is not counted as time in any position.
public struct TargetCoachEngine: Sendable, Equatable {

    /// Where a reading sits against the target. `below` means the wearer should do more (heart rate
    /// under the zone, or pace slower than asked); `above` means they should do less.
    public enum Position: Sendable, Equatable {
        case below, inside, above
    }

    public enum Cue: Sendable, Equatable {
        /// Below the target: pick it up.
        case pushOn
        /// Above the target: ease off.
        case easeOff
        /// Back inside the target after a cued excursion.
        case backInTarget
    }

    public struct Config: Sendable, Equatable {
        public var dwellSec: Double
        public var reminderSec: Double
        public var warmupSec: Double
        public var maxGapSec: Double

        public init(dwellSec: Double = 8, reminderSec: Double = 30, warmupSec: Double = 120,
                    maxGapSec: Double = 5) {
            self.dwellSec = max(0, dwellSec)
            self.reminderSec = max(1, reminderSec)
            self.warmupSec = max(0, warmupSec)
            self.maxGapSec = max(1, maxGapSec)
        }
    }

    public let config: Config

    /// The position the wearer has settled in, or nil before the first one settles.
    public private(set) var settled: Position?
    /// Active seconds spent in each position, by raw reading (not waiting for the dwell).
    public private(set) var secondsBelow: Double = 0
    public private(set) var secondsInside: Double = 0
    public private(set) var secondsAbove: Double = 0

    private var candidate: Position?
    private var candidateSince: Double = 0
    private var lastTime: Double?
    private var lastPosition: Position?
    private var lastCueAt: Double?
    private var excursionWasCued = false

    public init(config: Config = Config()) {
        self.config = config
    }

    /// Feed one reading taken at `time` (active elapsed seconds, never decreasing). Pass a nil
    /// position when there is nothing usable to judge (no heart rate, no pace yet, paused): it counts
    /// as a gap. Returns the cue to deliver now, if any.
    public mutating func ingest(position: Position?, at time: Double) -> Cue? {
        guard let position else {
            breakContinuity()
            return nil
        }

        if let lastTime, let lastPosition {
            let elapsed = time - lastTime
            if elapsed >= 0, elapsed <= config.maxGapSec {
                credit(elapsed, to: lastPosition)
            } else {
                // A gap, or a clock that went backwards: the dwell cannot be called continuous.
                candidate = nil
            }
        }
        lastTime = time
        lastPosition = position

        if position == settled {
            candidate = nil
        } else {
            if candidate != position {
                candidate = position
                candidateSince = time
            }
            if time - candidateSince >= config.dwellSec {
                settle(into: position)
            }
        }
        return dueCue(at: time)
    }

    /// Call when the session pauses or readings are known to have stopped. Equivalent to feeding a
    /// nil reading.
    public mutating func breakContinuity() {
        candidate = nil
        lastTime = nil
        lastPosition = nil
    }

    private mutating func credit(_ seconds: Double, to position: Position) {
        switch position {
        case .below: secondsBelow += seconds
        case .inside: secondsInside += seconds
        case .above: secondsAbove += seconds
        }
    }

    private mutating func settle(into position: Position) {
        settled = position
        candidate = nil
        // A new settled position restarts the reminder clock: its first cue is due at once.
        lastCueAt = nil
    }

    private mutating func dueCue(at time: Double) -> Cue? {
        guard let settled else { return nil }
        switch settled {
        case .inside:
            guard excursionWasCued, lastCueAt == nil else { return nil }
            excursionWasCued = false
            // Marks the "back in target" cue as delivered, so it is given once.
            lastCueAt = time
            return .backInTarget
        case .below, .above:
            if settled == .below, time < config.warmupSec { return nil }
            if let lastCueAt, time - lastCueAt < config.reminderSec { return nil }
            lastCueAt = time
            excursionWasCued = true
            return settled == .below ? .pushOn : .easeOff
        }
    }
}

/// A work-and-rest session: `reps` work bouts of `workSec`, with `restSec` between them. There is no
/// rest after the last rep.
public struct IntervalPlan: Sendable, Equatable, Codable {
    public var reps: Int
    public var workSec: Int
    public var restSec: Int

    public init(reps: Int, workSec: Int, restSec: Int) {
        self.reps = max(1, reps)
        self.workSec = max(1, workSec)
        self.restSec = max(0, restSec)
    }

    public var totalSec: Int { reps * workSec + (reps - 1) * restSec }
}

public enum IntervalPhase: Sendable, Equatable {
    /// Working on rep `rep` (1-based) of `of`, with `secondsLeft` in the bout.
    case work(rep: Int, of: Int, secondsLeft: Int)
    /// Resting after rep `rep`, with `secondsLeft` before the next bout.
    case rest(afterRep: Int, of: Int, secondsLeft: Int)
    /// Every rep is finished.
    case done
}

public enum IntervalClock {
    /// The phase a moment `activeElapsed` seconds into the session falls in.
    public static func phase(for plan: IntervalPlan, activeElapsed: Double) -> IntervalPhase {
        let t = max(0, activeElapsed)
        guard t < Double(plan.totalSec) else { return .done }
        let cycle = Double(plan.workSec + plan.restSec)
        let index = Int(t / cycle)                    // 0-based rep the moment falls in
        let within = t - Double(index) * cycle
        let rep = index + 1
        if within < Double(plan.workSec) {
            return .work(rep: rep, of: plan.reps, secondsLeft: Int((Double(plan.workSec) - within).rounded(.up)))
        }
        let restLeft = cycle - within
        return .rest(afterRep: rep, of: plan.reps, secondsLeft: Int(restLeft.rounded(.up)))
    }
}
