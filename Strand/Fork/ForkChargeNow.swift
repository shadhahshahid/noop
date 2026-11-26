import SwiftUI
import StrandAnalytics
import WhoopStore

// Personal fork: today's Charge, resolved once for every screen that shows it.
//
// Today's hero and its Charge tile show the resolved Charge (`LiquidTodayView.ChargeDisplay`): today's
// own score, else a real prior night's score stamped as such, and nothing while the baseline is still
// learning. The Data tab's Charge tile read the newest raw recovery value instead, so mid-calibration
// it showed a number Today withheld, and a stray future-dated row could reach it. Both now ask here.
// The selection rules are upstream's own (`RecoveryScorer.calibrationNights`,
// `TodayView.lastScoredRecoveryDay`, `ChargeDisplay.resolve`); this only gathers their inputs once.
enum ForkChargeNow {
    struct Resolved {
        /// What Today's hero draws for today.
        let display: LiquidTodayView.ChargeDisplay
        /// The day the shown score belongs to: today when scored, the prior night's day when carried,
        /// nil when there is no score to show.
        let scoredDayKey: String?
    }

    /// Today's Charge, as Today's hero resolves it on its own day (no day selected in the past).
    @MainActor
    static func resolve(repo: Repository) -> Resolved {
        let todayKey = repo.today?.day ?? Repository.localDayKey(Repository.logicalDay(Date()))
        let day = repo.today ?? repo.days.last(where: { $0.day == todayKey })
        let key = day?.day ?? todayKey
        let calibrationNights = RecoveryScorer.calibrationNights(
            nightlyHrv: repo.chargeBaselines?.hrvHistory.values ?? [],
            dayKeys: repo.chargeBaselines?.hrvHistory.dayKeys ?? [],
            hasRecovery: day?.recovery != nil)
        let prior = TodayView.lastScoredRecoveryDay(
            days: repo.days, selectedDayKey: key,
            isToday: true,
            todayScored: day?.recovery != nil,
            isCalibrating: calibrationNights != nil)
        let display = LiquidTodayView.ChargeDisplay.resolve(
            todayRecovery: day?.recovery,
            priorScored: prior,
            calibrationNights: calibrationNights,
            todayKey: key)
        let scoredDayKey: String?
        switch display {
        case .scored: scoredDayKey = key
        case .carried: scoredDayKey = prior?.day
        case .calibrating, .noData: scoredDayKey = nil
        }
        return Resolved(display: display, scoredDayKey: scoredDayKey)
    }
}
