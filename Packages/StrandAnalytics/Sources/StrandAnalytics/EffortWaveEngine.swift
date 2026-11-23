import Foundation

// Personal fork only (not upstream, no Android twin): picks the rounds out of an interval session
// from heart rate alone, so a HIIT session needs no setup.
//
// The idea is the simplest one that holds up: heart rate climbs while working and falls while
// recovering, so each round is one rise and one fall. A turn only counts once heart rate has moved
// back by `reversalBpm` from its extreme, which is what keeps beat-to-beat wobble from being read as
// rounds. Heart rate lags effort by some seconds, so the times found here trail the real ones; the
// COUNT of rounds, and the peak and trough of each, are what this is for.
//
// It is one pass, one reading at a time, so the same code gives the live "working or recovering"
// state during a session and the finished rounds afterwards. Pure: readings and times are supplied.
//
// Known limit, stated rather than hidden: strength stations raise heart rate much less than cardio
// ones, so a round of heavy lifting between two cardio rounds can be missed. Station marks (a
// double-tap on the strap) are the wearer's way to record what heart rate cannot show.
public struct EffortWaveEngine: Sendable, Equatable {

    public enum Phase: Sendable, Equatable {
        case working, recovering
    }

    /// One rise and (once it has happened) the fall after it.
    public struct Round: Sendable, Equatable {
        /// Heart rate and time at the top of the rise.
        public let peakBpm: Double
        public let peakAt: Double
        /// Heart rate and time at the bottom of the recovery that followed, once that recovery has
        /// turned back up. Nil for a round whose recovery is still going or was cut short.
        public var troughBpm: Double?
        public var troughAt: Double?

        /// How far heart rate came down after the peak, when known.
        public var recoveryDrop: Double? { troughBpm.map { peakBpm - $0 } }
    }

    public struct Config: Sendable, Equatable {
        /// How far heart rate must come back from an extreme before the turn counts.
        public var reversalBpm: Double
        /// A rise or fall shorter than this is not a round, however large.
        public var minLegSec: Double
        /// Smoothing applied to the raw readings before turns are looked for, as a time constant.
        /// Because it is weighted by the time between readings, a long gap needs no special case:
        /// the first reading after it simply replaces what came before.
        public var smoothingSec: Double

        public init(reversalBpm: Double = 10, minLegSec: Double = 20, smoothingSec: Double = 8) {
            self.reversalBpm = max(1, reversalBpm)
            self.minLegSec = max(0, minLegSec)
            self.smoothingSec = max(0, smoothingSec)
        }
    }

    public let config: Config

    /// Rounds whose peak has been confirmed, oldest first.
    public private(set) var rounds: [Round] = []
    /// Working or recovering, or nil until heart rate has made its first clear move.
    public private(set) var phase: Phase?
    /// The smoothed heart rate turns are judged on, or nil before the first reading.
    public private(set) var smoothedBpm: Double?

    private var lastTime: Double?
    private var extremeBpm: Double = 0
    private var extremeAt: Double = 0
    private var legStartedAt: Double = 0
    /// When the rise of the most recently confirmed round began, kept so that round can be taken back
    /// if the "recovery" after it turns out to be a brief dip.
    private var riseStartOfLastRound: Double = 0
    /// Before the first clear move: the lowest and highest smoothed readings so far.
    private var openingLow: (bpm: Double, at: Double)?
    private var openingHigh: (bpm: Double, at: Double)?

    public init(config: Config = Config()) {
        self.config = config
    }

    /// The round the wearer is in, 1-based: the one being worked on, or the one being recovered from.
    /// Zero until the first rise has begun.
    public var currentRound: Int {
        switch phase {
        case .none: return 0
        case .working: return rounds.count + 1
        case .recovering: return rounds.count
        }
    }

    /// Feed one heart-rate reading taken at `time` (active elapsed seconds, never decreasing).
    public mutating func ingest(bpm: Double, at time: Double) {
        guard bpm.isFinite, bpm > 0 else { return }

        let value: Double
        if let previous = smoothedBpm, let lastTime, time >= lastTime {
            if config.smoothingSec <= 0 {
                value = bpm
            } else {
                let weight = 1 - exp(-(time - lastTime) / config.smoothingSec)
                value = previous + (bpm - previous) * weight
            }
        } else {
            value = bpm
        }
        smoothedBpm = value
        lastTime = time

        switch phase {
        case .none:
            if openingLow == nil || value < openingLow!.bpm { openingLow = (value, time) }
            if openingHigh == nil || value > openingHigh!.bpm { openingHigh = (value, time) }
            if let low = openingLow, value - low.bpm >= config.reversalBpm {
                // A clear rise from the lowest point so far: the first round has begun there.
                phase = .working
                legStartedAt = low.at
                extremeBpm = value
                extremeAt = time
            } else if let high = openingHigh, high.bpm - value >= config.reversalBpm {
                // The session opened with a clear fall (started mid-effort): recovering, with no
                // round to its name.
                phase = .recovering
                legStartedAt = high.at
                extremeBpm = value
                extremeAt = time
            }
        case .working:
            if value >= extremeBpm {
                extremeBpm = value
                extremeAt = time
            } else if extremeBpm - value >= config.reversalBpm {
                if extremeAt - legStartedAt >= config.minLegSec {
                    // A real rise has ended: that is a round.
                    rounds.append(Round(peakBpm: extremeBpm, peakAt: extremeAt, troughBpm: nil, troughAt: nil))
                    riseStartOfLastRound = legStartedAt
                }
                // Too short a rise is a blip, not a round; either way heart rate is now falling.
                phase = .recovering
                legStartedAt = extremeAt
                extremeBpm = value
                extremeAt = time
            }
        case .recovering:
            if value <= extremeBpm {
                extremeBpm = value
                extremeAt = time
            } else if value - extremeBpm >= config.reversalBpm {
                let fallWasReal = extremeAt - legStartedAt >= config.minLegSec
                if fallWasReal {
                    if !rounds.isEmpty, rounds[rounds.count - 1].troughAt == nil {
                        rounds[rounds.count - 1].troughBpm = extremeBpm
                        rounds[rounds.count - 1].troughAt = extremeAt
                    }
                    legStartedAt = extremeAt
                    extremeBpm = value
                    extremeAt = time
                } else if let last = rounds.last, last.peakAt == legStartedAt, last.troughAt == nil {
                    // A brief dip in the middle of one effort: the "peak" before it did not end the
                    // round after all. Take that round back and carry on with the same rise.
                    rounds.removeLast()
                    legStartedAt = riseStartOfLastRound
                    if value >= last.peakBpm {
                        extremeBpm = value
                        extremeAt = time
                    } else {
                        extremeBpm = last.peakBpm
                        extremeAt = last.peakAt
                    }
                } else {
                    legStartedAt = extremeAt
                    extremeBpm = value
                    extremeAt = time
                }
                phase = .working
            }
        }
    }

    /// Rounds whose peak fell in `range` (active elapsed seconds), for counting rounds per station.
    public func rounds(in range: Range<Double>) -> [Round] {
        rounds.filter { range.contains($0.peakAt) }
    }

    public static func == (lhs: EffortWaveEngine, rhs: EffortWaveEngine) -> Bool {
        lhs.config == rhs.config && lhs.rounds == rhs.rounds && lhs.phase == rhs.phase
            && lhs.smoothedBpm == rhs.smoothedBpm
    }
}
