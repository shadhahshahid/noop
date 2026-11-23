import Foundation

// Personal fork only (not upstream, no Android twin): the arithmetic behind the fork's Training
// screen. Pure: sessions, "now" and the calendar are all supplied, so every figure can be tested
// exactly. Nothing here is a new score; it only groups and counts sessions the app already has.
public enum TrainingOverview {

    /// One session, reduced to what the overview needs.
    public struct Session: Sendable, Equatable {
        public let start: Date
        /// The session's Effort (0 to 100), when it was scored.
        public let load: Double?
        public let seconds: Double

        public init(start: Date, load: Double?, seconds: Double) {
            self.start = start
            self.load = load
            self.seconds = max(0, seconds)
        }
    }

    public struct Week: Sendable, Equatable {
        /// The first moment of the week, in the supplied calendar.
        public let start: Date
        /// The sum of the Effort of every scored session that week.
        public let load: Double
        public let sessions: Int
        public let minutes: Double
    }

    /// The last `count` calendar weeks, oldest first, ending with the week that contains `now`.
    /// Weeks with no sessions are present with zeros, so the bars never skip a week.
    public static func weeks(_ sessions: [Session], now: Date, count: Int = 6,
                             calendar: Calendar) -> [Week] {
        guard count > 0, let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        var starts: [Date] = []
        for back in stride(from: count - 1, through: 0, by: -1) {
            if let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek) { starts.append(start) }
        }
        return starts.map { start in
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            let inside = sessions.filter { $0.start >= start && $0.start < end }
            return Week(start: start,
                        load: inside.compactMap(\.load).reduce(0, +),
                        sessions: inside.count,
                        minutes: inside.map(\.seconds).reduce(0, +) / 60)
        }
    }

    /// How the newest week's load compares with the average of the weeks before it, as a fraction
    /// (0.18 = 18% above). Nil when there are no earlier weeks with any load to compare against.
    /// Earlier weeks with no sessions at all are left out of "usual": a fortnight off should not
    /// make an ordinary week look like a spike.
    public static func changeVersusUsual(_ weeks: [Week]) -> Double? {
        guard let newest = weeks.last else { return nil }
        let earlier = weeks.dropLast().filter { $0.load > 0 }
        guard !earlier.isEmpty else { return nil }
        let usual = earlier.map(\.load).reduce(0, +) / Double(earlier.count)
        guard usual > 0 else { return nil }
        return (newest.load - usual) / usual
    }

    public struct Streak: Sendable, Equatable {
        /// Days in a row with at least one session, counting back from today, or from yesterday
        /// when today has none yet (the day is not over, so the streak is not broken).
        public let current: Int
        /// One flag per day for the last `window` days, oldest first, the last being today.
        public let days: [Bool]
        public var daysDone: Int { days.filter { $0 }.count }
    }

    public static func streak(sessionStarts: [Date], now: Date, window: Int = 28,
                              calendar: Calendar) -> Streak {
        let today = calendar.startOfDay(for: now)
        let done = Set(sessionStarts.map { calendar.startOfDay(for: $0) })
        func day(_ back: Int) -> Date { calendar.date(byAdding: .day, value: -back, to: today) ?? today }

        var current = 0
        var back = done.contains(today) ? 0 : 1
        while done.contains(day(back)) {
            current += 1
            back += 1
        }
        let size = max(0, window)
        let flags = (0..<size).map { index in done.contains(day(size - 1 - index)) }
        return Streak(current: current, days: flags)
    }
}
