import XCTest
@testable import StrandAnalytics

/// Personal fork only: pins every rule of the run coach (`TargetCoachEngine`) and the interval
/// clock. Pure: readings and times are supplied, so nothing here waits or needs a strap.
final class TargetCoachEngineTests: XCTestCase {

    private typealias Position = TargetCoachEngine.Position
    private typealias Cue = TargetCoachEngine.Cue

    /// Feeds one reading per second from `start` for `seconds` seconds and returns every cue with
    /// the second it was given at.
    private func feed(_ engine: inout TargetCoachEngine, _ position: Position?, from start: Int,
                      seconds: Int) -> [(time: Int, cue: Cue)] {
        var cues: [(time: Int, cue: Cue)] = []
        for second in start..<(start + seconds) {
            if let cue = engine.ingest(position: position, at: Double(second)) {
                cues.append((second, cue))
            }
        }
        return cues
    }

    private func noWarmup() -> TargetCoachEngine {
        TargetCoachEngine(config: .init(warmupSec: 0))
    }

    // MARK: Dwell

    func testSilentWhileInsideTheTarget() {
        var engine = noWarmup()
        XCTAssertTrue(feed(&engine, .inside, from: 0, seconds: 600).isEmpty)
        XCTAssertEqual(engine.settled, .inside)
    }

    func testBelowMustHoldForTheDwellBeforeItCues() {
        var engine = noWarmup()
        _ = feed(&engine, .inside, from: 0, seconds: 20)
        // Seven seconds below is not enough.
        XCTAssertTrue(feed(&engine, .below, from: 20, seconds: 8).isEmpty)
        // The eighth full second below settles it: the reading at 28 is 8 s after the one at 20.
        let cues = feed(&engine, .below, from: 28, seconds: 1)
        XCTAssertEqual(cues.map(\.cue), [.pushOn])
        XCTAssertEqual(cues.first?.time, 28)
    }

    func testAStrayReadingAcrossTheBoundaryChangesNothing() {
        var engine = noWarmup()
        _ = feed(&engine, .inside, from: 0, seconds: 20)
        var cues: [Cue] = []
        // Above for 7 s, inside for 1 s, over and over: never 8 s in a row.
        var second = 20
        for _ in 0..<10 {
            cues += feed(&engine, .above, from: second, seconds: 7).map(\.cue); second += 7
            cues += feed(&engine, .inside, from: second, seconds: 1).map(\.cue); second += 1
        }
        XCTAssertTrue(cues.isEmpty)
        XCTAssertEqual(engine.settled, .inside)
    }

    // MARK: Cues

    func testAboveCuesEaseOffThenBackInTargetOnce() {
        var engine = noWarmup()
        _ = feed(&engine, .inside, from: 0, seconds: 20)
        let up = feed(&engine, .above, from: 20, seconds: 12)
        XCTAssertEqual(up.map(\.cue), [.easeOff])
        let back = feed(&engine, .inside, from: 32, seconds: 120)
        XCTAssertEqual(back.map(\.cue), [.backInTarget])
        XCTAssertEqual(back.first?.time, 40)   // 8 s after the first inside reading at 32
    }

    func testReminderRepeatsEveryThirtySecondsWhileOutOfTarget() {
        var engine = noWarmup()
        _ = feed(&engine, .inside, from: 0, seconds: 20)
        let cues = feed(&engine, .below, from: 20, seconds: 90)   // readings at 20 … 109
        XCTAssertEqual(cues.map(\.cue), [.pushOn, .pushOn, .pushOn])
        XCTAssertEqual(cues.map(\.time), [28, 58, 88])
    }

    func testGoingStraightFromBelowToAboveCuesEaseOffAtOnce() {
        var engine = noWarmup()
        _ = feed(&engine, .below, from: 0, seconds: 10)            // pushOn at 8
        let cues = feed(&engine, .above, from: 10, seconds: 10)
        XCTAssertEqual(cues.map(\.cue), [.easeOff])
        XCTAssertEqual(cues.first?.time, 18)   // not held back by the push-on reminder clock
    }

    // MARK: Warm-up

    func testPushOnIsHeldBackDuringTheWarmupThenGiven() {
        var engine = TargetCoachEngine()   // default 120 s warm-up
        let cues = feed(&engine, .below, from: 0, seconds: 125)
        XCTAssertEqual(cues.map(\.cue), [.pushOn])
        XCTAssertEqual(cues.first?.time, 120)
    }

    func testEaseOffIsNeverHeldBackByTheWarmup() {
        var engine = TargetCoachEngine()
        let cues = feed(&engine, .above, from: 0, seconds: 12)
        XCTAssertEqual(cues.map(\.cue), [.easeOff])
        XCTAssertEqual(cues.first?.time, 8)
    }

    func testReachingTheTargetAfterAnUncuedWarmupIsSilent() {
        var engine = TargetCoachEngine()
        // Below for the first minute (inside the warm-up, so never cued), then in the target.
        XCTAssertTrue(feed(&engine, .below, from: 0, seconds: 60).isEmpty)
        XCTAssertTrue(feed(&engine, .inside, from: 60, seconds: 300).isEmpty)
    }

    func testBackInTargetIsOnlyGivenForAnExcursionThatWasCued() {
        var engine = TargetCoachEngine()   // default 120 s warm-up
        // A cued excursion above, and its "back in target".
        XCTAssertEqual(feed(&engine, .above, from: 0, seconds: 10).map(\.cue), [.easeOff])
        XCTAssertEqual(feed(&engine, .inside, from: 10, seconds: 20).map(\.cue), [.backInTarget])
        // Then a dip below while still warming up, which is not cued, so returning is silent too.
        XCTAssertTrue(feed(&engine, .below, from: 30, seconds: 20).isEmpty)
        XCTAssertTrue(feed(&engine, .inside, from: 50, seconds: 60).isEmpty)
    }

    // MARK: Gaps and pauses

    func testAGapInReadingsBreaksTheDwell() {
        var engine = noWarmup()
        _ = feed(&engine, .inside, from: 0, seconds: 20)
        XCTAssertTrue(feed(&engine, .above, from: 20, seconds: 5).isEmpty)
        // Readings stop for 30 s, then resume above: the earlier 5 s must not count.
        XCTAssertTrue(feed(&engine, .above, from: 55, seconds: 8).isEmpty)
        XCTAssertEqual(feed(&engine, .above, from: 63, seconds: 1).map(\.cue), [.easeOff])
    }

    func testANilReadingBreaksTheDwellAndIsNotCounted() {
        var engine = noWarmup()
        _ = feed(&engine, .inside, from: 0, seconds: 20)
        XCTAssertTrue(feed(&engine, .above, from: 20, seconds: 6).isEmpty)
        XCTAssertNil(engine.ingest(position: nil, at: 26))
        XCTAssertTrue(feed(&engine, .above, from: 27, seconds: 8).isEmpty)
        XCTAssertEqual(feed(&engine, .above, from: 35, seconds: 1).map(\.cue), [.easeOff])
    }

    func testTimeInEachPositionCountsReadingsButNotGaps() {
        var engine = noWarmup()
        _ = feed(&engine, .inside, from: 0, seconds: 61)    // 60 s credited to inside
        _ = feed(&engine, .above, from: 61, seconds: 30)    // 1 s more inside (60 to 61), 29 s above
        _ = feed(&engine, .below, from: 300, seconds: 11)   // after a long gap: 10 s below
        XCTAssertEqual(engine.secondsInside, 61, accuracy: 0.001)
        XCTAssertEqual(engine.secondsAbove, 29, accuracy: 0.001)
        XCTAssertEqual(engine.secondsBelow, 10, accuracy: 0.001)
    }

    func testAClockThatGoesBackwardsIsTreatedAsAGap() {
        var engine = noWarmup()
        _ = feed(&engine, .above, from: 100, seconds: 5)
        XCTAssertNil(engine.ingest(position: .above, at: 50))
        XCTAssertEqual(engine.secondsAbove, 4, accuracy: 0.001)
        XCTAssertNil(engine.settled)
    }

    // MARK: Interval clock

    func testIntervalClockWalksWorkAndRest() {
        let plan = IntervalPlan(reps: 3, workSec: 120, restSec: 60)
        XCTAssertEqual(plan.totalSec, 480)   // 3 × 120 + 2 × 60: no rest after the last rep
        XCTAssertEqual(IntervalClock.phase(for: plan, activeElapsed: 0), .work(rep: 1, of: 3, secondsLeft: 120))
        XCTAssertEqual(IntervalClock.phase(for: plan, activeElapsed: 119.5), .work(rep: 1, of: 3, secondsLeft: 1))
        XCTAssertEqual(IntervalClock.phase(for: plan, activeElapsed: 120), .rest(afterRep: 1, of: 3, secondsLeft: 60))
        XCTAssertEqual(IntervalClock.phase(for: plan, activeElapsed: 179), .rest(afterRep: 1, of: 3, secondsLeft: 1))
        XCTAssertEqual(IntervalClock.phase(for: plan, activeElapsed: 180), .work(rep: 2, of: 3, secondsLeft: 120))
        XCTAssertEqual(IntervalClock.phase(for: plan, activeElapsed: 360), .work(rep: 3, of: 3, secondsLeft: 120))
        XCTAssertEqual(IntervalClock.phase(for: plan, activeElapsed: 479), .work(rep: 3, of: 3, secondsLeft: 1))
        XCTAssertEqual(IntervalClock.phase(for: plan, activeElapsed: 480), .done)
        XCTAssertEqual(IntervalClock.phase(for: plan, activeElapsed: 9999), .done)
    }

    func testIntervalClockWithNoRestAndWithBadInput() {
        let back = IntervalPlan(reps: 2, workSec: 30, restSec: 0)
        XCTAssertEqual(IntervalClock.phase(for: back, activeElapsed: 29), .work(rep: 1, of: 2, secondsLeft: 1))
        XCTAssertEqual(IntervalClock.phase(for: back, activeElapsed: 30), .work(rep: 2, of: 2, secondsLeft: 30))
        XCTAssertEqual(IntervalClock.phase(for: back, activeElapsed: 60), .done)
        // Nonsense values are clamped rather than trapping.
        let clamped = IntervalPlan(reps: 0, workSec: -5, restSec: -5)
        XCTAssertEqual(clamped, IntervalPlan(reps: 1, workSec: 1, restSec: 0))
        XCTAssertEqual(IntervalClock.phase(for: clamped, activeElapsed: -3), .work(rep: 1, of: 1, secondsLeft: 1))
    }
}
