import XCTest
@testable import StrandAnalytics

/// Personal fork only: pins the grouping and counting behind the fork's Training screen.
final class TrainingOverviewTests: XCTestCase {

    /// A fixed calendar (UTC, weeks start on Monday) so the tests do not depend on the machine.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func session(_ year: Int, _ month: Int, _ day: Int, load: Double? = 40, minutes: Double = 30) -> TrainingOverview.Session {
        .init(start: date(year, month, day), load: load, seconds: minutes * 60)
    }

    // MARK: Weeks

    func testGroupsSessionsIntoCalendarWeeksOldestFirst() {
        // Monday 23 Nov 2026 is "now"; that week runs 23 to 29 Nov.
        let now = date(2026, 11, 23)
        let sessions = [
            session(2026, 11, 23, load: 50, minutes: 45),            // this week
            session(2026, 11, 22, load: 30),                         // Sunday: last week
            session(2026, 11, 16, load: 20),                         // Monday of last week
            session(2026, 11, 3, load: 60), session(2026, 11, 5, load: nil),   // three weeks back, one unscored
            session(2026, 9, 1, load: 99),                           // too old to appear
        ]
        let weeks = TrainingOverview.weeks(sessions, now: now, count: 4, calendar: calendar)
        XCTAssertEqual(weeks.count, 4)
        XCTAssertEqual(weeks.map(\.start), [date(2026, 11, 2, 0), date(2026, 11, 9, 0), date(2026, 11, 16, 0), date(2026, 11, 23, 0)])
        XCTAssertEqual(weeks.map(\.load), [60, 0, 50, 50])
        XCTAssertEqual(weeks.map(\.sessions), [2, 0, 2, 1])
        XCTAssertEqual(weeks.last?.minutes ?? 0, 45, accuracy: 0.001)
    }

    func testAnEmptyHistoryStillGivesEveryWeek() {
        let weeks = TrainingOverview.weeks([], now: date(2026, 11, 23), calendar: calendar)
        XCTAssertEqual(weeks.count, 6)
        XCTAssertTrue(weeks.allSatisfy { $0.load == 0 && $0.sessions == 0 })
        XCTAssertTrue(TrainingOverview.weeks([], now: date(2026, 11, 23), count: 0, calendar: calendar).isEmpty)
    }

    func testASessionAtTheFirstInstantOfAWeekBelongsToThatWeek() {
        let boundary = TrainingOverview.Session(start: date(2026, 11, 23, 0), load: 10, seconds: 60)
        let weeks = TrainingOverview.weeks([boundary], now: date(2026, 11, 25), count: 2, calendar: calendar)
        XCTAssertEqual(weeks.map(\.sessions), [0, 1])
    }

    // MARK: Change against usual

    func testChangeIsMeasuredAgainstTheAverageOfEarlierWeeks() {
        func week(_ load: Double) -> TrainingOverview.Week { .init(start: Date(), load: load, sessions: 1, minutes: 0) }
        XCTAssertEqual(TrainingOverview.changeVersusUsual([week(100), week(200), week(177)]) ?? 0, 0.18, accuracy: 0.0001)
        XCTAssertEqual(TrainingOverview.changeVersusUsual([week(100), week(50)]) ?? 0, -0.5, accuracy: 0.0001)
        // Weeks off are not part of "usual".
        XCTAssertEqual(TrainingOverview.changeVersusUsual([week(0), week(100), week(0), week(150)]) ?? 0, 0.5, accuracy: 0.0001)
    }

    func testChangeIsUnknownWithNothingToCompareAgainst() {
        func week(_ load: Double) -> TrainingOverview.Week { .init(start: Date(), load: load, sessions: 1, minutes: 0) }
        XCTAssertNil(TrainingOverview.changeVersusUsual([]))
        XCTAssertNil(TrainingOverview.changeVersusUsual([week(80)]))
        XCTAssertNil(TrainingOverview.changeVersusUsual([week(0), week(0), week(80)]))
    }

    // MARK: Streak

    func testStreakCountsBackFromTodayWhenTodayIsDone() {
        let now = date(2026, 11, 23, 9)
        let starts = [date(2026, 11, 23, 7), date(2026, 11, 22), date(2026, 11, 21), date(2026, 11, 19)]
        let streak = TrainingOverview.streak(sessionStarts: starts, now: now, window: 7, calendar: calendar)
        XCTAssertEqual(streak.current, 3)
        // 17 to 23 Nov, oldest first.
        XCTAssertEqual(streak.days, [false, false, true, false, true, true, true])
        XCTAssertEqual(streak.daysDone, 4)
    }

    func testStreakIsNotBrokenByATodayThatHasNotHappenedYet() {
        let now = date(2026, 11, 23, 6)
        let starts = [date(2026, 11, 22), date(2026, 11, 21)]
        XCTAssertEqual(TrainingOverview.streak(sessionStarts: starts, now: now, calendar: calendar).current, 2)
    }

    func testStreakIsZeroAfterAMissedDay() {
        let now = date(2026, 11, 23, 20)
        let starts = [date(2026, 11, 21), date(2026, 11, 20)]
        let streak = TrainingOverview.streak(sessionStarts: starts, now: now, window: 28, calendar: calendar)
        XCTAssertEqual(streak.current, 0)
        XCTAssertEqual(streak.days.count, 28)
        XCTAssertEqual(streak.daysDone, 2)
    }

    func testTwoSessionsOnOneDayCountOnce() {
        let now = date(2026, 11, 23, 20)
        let starts = [date(2026, 11, 23, 6), date(2026, 11, 23, 18)]
        let streak = TrainingOverview.streak(sessionStarts: starts, now: now, window: 3, calendar: calendar)
        XCTAssertEqual(streak.current, 1)
        XCTAssertEqual(streak.days, [false, false, true])
    }
}
