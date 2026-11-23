import XCTest
@testable import StrandAnalytics

/// Personal fork only: pins how rounds are picked out of heart rate (`EffortWaveEngine`). Curves
/// are generated here, with a fixed pseudo-random wobble, so each test is exact and repeatable and
/// the method is shown to TRACK the number of rounds put in, not to match one lucky case.
final class EffortWaveEngineTests: XCTestCase {

    /// A deterministic wobble in -1...1, so "noise" is the same on every run and every machine.
    private struct Wobble {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 2001) / 1000.0 - 1.0
        }
    }

    /// One reading a second: `rounds` efforts, each rising from `low` to `high` over `workSec` and
    /// falling back over `restSec`, after `leadSec` at `low`, with up to ±`noise` bpm of wobble.
    private func session(rounds: Int, workSec: Int, restSec: Int, low: Double = 120, high: Double = 170,
                         leadSec: Int = 60, noise: Double = 2, seed: UInt64 = 7) -> [(time: Double, bpm: Double)] {
        var wobble = Wobble(seed: seed)
        var out: [(Double, Double)] = []
        var t = 0
        for _ in 0..<leadSec { out.append((Double(t), low + wobble.next() * noise)); t += 1 }
        for _ in 0..<rounds {
            for i in 0..<workSec {
                let level = low + (high - low) * Double(i + 1) / Double(workSec)
                out.append((Double(t), level + wobble.next() * noise)); t += 1
            }
            for i in 0..<restSec {
                let level = high - (high - low) * Double(i + 1) / Double(restSec)
                out.append((Double(t), level + wobble.next() * noise)); t += 1
            }
        }
        return out
    }

    private func run(_ readings: [(time: Double, bpm: Double)], config: EffortWaveEngine.Config = .init()) -> EffortWaveEngine {
        var engine = EffortWaveEngine(config: config)
        for reading in readings { engine.ingest(bpm: reading.bpm, at: reading.time) }
        return engine
    }

    // MARK: Counting rounds

    func testCountsTheRoundsPutInAcrossManySessionShapes() {
        for rounds in [1, 3, 5, 8, 12, 20] {
            for (work, rest) in [(45, 45), (60, 30), (120, 90), (240, 120)] {
                for seed: UInt64 in [1, 7, 99] {
                    let engine = run(session(rounds: rounds, workSec: work, restSec: rest, seed: seed))
                    XCTAssertEqual(engine.rounds.count, rounds,
                                   "\(rounds) rounds of \(work)/\(rest) s, seed \(seed)")
                }
            }
        }
    }

    /// Readings that jump about by ±7 bpm from one second to the next. Without the smoothing the
    /// wobble alone crosses the reversal threshold and the count comes out wrong.
    func testCountsRoundsThroughHeavyWobble() {
        for rounds in [2, 6, 10] {
            for seed: UInt64 in [5, 42] {
                let engine = run(session(rounds: rounds, workSec: 90, restSec: 75, noise: 7, seed: seed))
                XCTAssertEqual(engine.rounds.count, rounds, "\(rounds) rounds, seed \(seed)")
            }
        }
    }

    func testFindsPeaksAndTroughsCloseToTheOnesPutIn() {
        let engine = run(session(rounds: 4, workSec: 90, restSec: 60, low: 115, high: 172, noise: 1))
        XCTAssertEqual(engine.rounds.count, 4)
        for (index, round) in engine.rounds.enumerated() {
            XCTAssertEqual(round.peakBpm, 172, accuracy: 6, "round \(index + 1) peak")
            // Peaks fall at the end of each work bout: 60 s lead, then every 150 s.
            XCTAssertEqual(round.peakAt, Double(60 + 90 + index * 150), accuracy: 12, "round \(index + 1) peak time")
        }
        // Every recovery but the last has turned back up, so its trough is known.
        for round in engine.rounds.dropLast() {
            XCTAssertEqual(round.troughBpm ?? 0, 115, accuracy: 6)
            XCTAssertEqual(round.recoveryDrop ?? 0, 57, accuracy: 10)
        }
    }

    // MARK: Not counting what is not a round

    func testASteadyEffortIsNotSplitIntoRounds() {
        var wobble = Wobble(seed: 3)
        var engine = EffortWaveEngine()
        // Twenty minutes around 150 bpm with ±4 bpm of wobble.
        for second in 0..<1200 { engine.ingest(bpm: 150 + wobble.next() * 4, at: Double(second)) }
        XCTAssertEqual(engine.rounds.count, 0)
    }

    func testABriefDipInsideOneEffortDoesNotMakeTwoRounds() {
        var engine = EffortWaveEngine(config: .init(smoothingSec: 0))
        var t = 0.0
        func feed(_ bpm: Double, seconds: Int) {
            for _ in 0..<seconds { engine.ingest(bpm: bpm, at: t); t += 1 }
        }
        feed(120, seconds: 30)
        for i in 0..<60 { engine.ingest(bpm: 120 + Double(i), at: t); t += 1 }   // rise to 179 over a minute
        feed(165, seconds: 8)                                                   // an 8-second dip of 14 bpm
        for i in 0..<20 { engine.ingest(bpm: 165 + Double(i), at: t); t += 1 }   // carries on up to 184
        XCTAssertEqual(engine.rounds.count, 0, "the effort is still going")
        XCTAssertEqual(engine.phase, .working)
        feed(130, seconds: 60)                                                  // then a real recovery
        XCTAssertEqual(engine.rounds.count, 1)
        XCTAssertEqual(engine.rounds.first?.peakBpm ?? 0, 184, accuracy: 0.5)
    }

    func testAShortSpikeDuringRecoveryIsNotARound() {
        var engine = EffortWaveEngine(config: .init(smoothingSec: 0))
        var t = 0.0
        func feed(_ bpm: Double, seconds: Int) {
            for _ in 0..<seconds { engine.ingest(bpm: bpm, at: t); t += 1 }
        }
        feed(120, seconds: 20)
        for i in 0..<60 { engine.ingest(bpm: 120 + Double(i), at: t); t += 1 }   // one real round
        feed(140, seconds: 30)
        feed(155, seconds: 6)                                                   // a 6-second spike
        feed(125, seconds: 60)
        XCTAssertEqual(engine.rounds.count, 1)
        XCTAssertEqual(engine.phase, .recovering)
    }

    // MARK: Live state

    func testPhaseAndCurrentRoundFollowTheSession() {
        let readings = session(rounds: 3, workSec: 60, restSec: 60, noise: 0)
        var engine = EffortWaveEngine()
        var seen: [Double: (EffortWaveEngine.Phase?, Int)] = [:]
        for reading in readings {
            engine.ingest(bpm: reading.bpm, at: reading.time)
            seen[reading.time] = (engine.phase, engine.currentRound)
        }
        XCTAssertNil(seen[30]?.0)                       // still in the flat lead-in
        XCTAssertEqual(seen[30]?.1, 0)
        XCTAssertEqual(seen[110]?.0, .working)          // late in the first work bout
        XCTAssertEqual(seen[110]?.1, 1)
        XCTAssertEqual(seen[170]?.0, .recovering)       // late in the first recovery
        XCTAssertEqual(seen[170]?.1, 1)
        XCTAssertEqual(seen[230]?.0, .working)          // late in the second work bout
        XCTAssertEqual(seen[230]?.1, 2)
        XCTAssertEqual(seen[410]?.0, .recovering)       // late in the last recovery
        XCTAssertEqual(seen[410]?.1, 3)
    }

    func testRoundsCanBeCountedPerStation() {
        let engine = run(session(rounds: 6, workSec: 60, restSec: 60, noise: 1))
        XCTAssertEqual(engine.rounds.count, 6)
        // Peaks at about 120, 240, 360, 480, 600, 720 s. A station mark at 400 s splits them 3 and 3.
        XCTAssertEqual(engine.rounds(in: 0..<400).count, 3)
        XCTAssertEqual(engine.rounds(in: 400..<10_000).count, 3)
    }

    // MARK: Awkward input

    func testIgnoresImpossibleReadingsAndSurvivesGaps() {
        var engine = EffortWaveEngine()
        engine.ingest(bpm: 0, at: 0)
        engine.ingest(bpm: -5, at: 1)
        engine.ingest(bpm: .nan, at: 2)
        XCTAssertNil(engine.smoothedBpm)
        // Two rounds, a five-minute gap with no readings, then two more.
        let first = session(rounds: 2, workSec: 60, restSec: 60, noise: 1)
        for reading in first { engine.ingest(bpm: reading.bpm, at: reading.time + 10) }
        let later = session(rounds: 2, workSec: 60, restSec: 60, leadSec: 30, noise: 1, seed: 11)
        for reading in later { engine.ingest(bpm: reading.bpm, at: reading.time + 700) }
        XCTAssertEqual(engine.rounds.count, 4)
    }
}
