import XCTest
@testable import Strand

/// Pins when Today's liquid sky runs its 20 fps frame loop: only while a star can be drawn AND seen to twinkle.
///
/// The breath of light is the sky's one other moving layer, and it changes no pixel by more than a few of 255
/// levels, so an hour with no drawable star gains nothing from redrawing and the loop stands down. Pure, so it
/// needs no view, no clock and no simulator.
final class LiquidSkyMotionTests: XCTestCase {

    func testStarlessDaytimeHoursPauseTheLoop() {
        for light in [false, true] {
            for hour in [9.0, 12.0, 15.25, 17.5, 18.5, 19.0] {
                XCTAssertTrue(LiquidSky.pausesFrames(hour: hour, light: light, poseStill: false),
                              "hour \(hour), light \(light)")
            }
        }
    }

    /// Personal fork: the dark sky is one near-black atmosphere with no stars at any hour (see
    /// `liquidSkyKeys`), so there is never a star to twinkle and the frame loop never runs. Upstream
    /// pinned the opposite here (`testStarryHoursKeepTheTwinkleInDarkAppearance`): its dark sky had stars
    /// at night.
    func testForkDarkSkyHasNoStarsAndNeverRunsTheLoop() {
        for minute in 0..<(24 * 60) {
            let hour = Double(minute) / 60
            XCTAssertFalse(liquidSkyHasVisibleStars(liquidSkyAt(hour, light: false).stars), "minute \(minute)")
            XCTAssertTrue(LiquidSky.pausesFrames(hour: hour, light: false, poseStill: false), "minute \(minute)")
        }
    }

    /// White stars on the near-white light sky never move a pixel by `liquidStarMinLift` levels, so light appearance
    /// never runs the loop, at any minute.
    func testLightAppearanceNeverRunsTheLoop() {
        for minute in 0..<(24 * 60) {
            let hour = Double(minute) / 60
            XCTAssertLessThan(liquidStarPeakLift(hour: hour, light: true), liquidStarMinLift, "minute \(minute)")
            XCTAssertTrue(LiquidSky.pausesFrames(hour: hour, light: true, poseStill: false), "minute \(minute)")
        }
    }

    /// Dark appearance is untouched: at every minute the loop runs exactly when a star can be drawn, as before the
    /// lift rule, because a drawable star on the dark sky always lifts its pixel past `liquidStarMinLift`.
    func testDarkAppearanceStillFollowsTheDrawableStars() {
        for minute in 0..<(24 * 60) {
            let hour = Double(minute) / 60
            let drawable = liquidSkyHasVisibleStars(liquidSkyAt(hour, light: false).stars)
            XCTAssertEqual(LiquidSky.pausesFrames(hour: hour, light: false, poseStill: false), !drawable,
                           "minute \(minute)")
            if drawable {
                XCTAssertGreaterThanOrEqual(liquidStarPeakLift(hour: hour, light: false), liquidStarMinLift,
                                            "minute \(minute)")
            }
        }
    }

    /// Reduce Motion, Low Power Mode and the in-app toggle still pause it at any hour.
    func testPoseStillPausesEvenUnderStars() {
        XCTAssertTrue(LiquidSky.pausesFrames(hour: 0, light: false, poseStill: true))
        XCTAssertTrue(LiquidSky.pausesFrames(hour: 23.5, light: true, poseStill: true))
    }

    // Personal fork: upstream's `testTheLoopFollowsTheDrawableStarsAtDawnAndDusk` pinned the minutes
    // at which stars fade in and out of the dark sky. The fork's dark sky has no stars, so there is no
    // such crossing to pin; `testForkDarkSkyHasNoStarsAndNeverRunsTheLoop` covers the whole day instead.

    /// At every minute of the day, in both appearances: while the loop is stopped no star, at any depth and at any
    /// point of its twinkle, both reaches the drawing floor and lifts a pixel by `liquidStarMinLift` levels, so
    /// stopping it never freezes a star someone could see; and while it runs, the nearest star at its peak does both.
    func testTheLoopStopsOnlyWhenNoStarCanBeDrawn() {
        let steps = (0...20).map { Double($0) / 20 }
        for minute in 0..<(24 * 60) {
            let hour = Double(minute) / 60
            for light in [false, true] {
                let stars = liquidSkyAt(hour, light: light).stars
                let lift = liquidStarPeakLift(hour: hour, light: light)
                if LiquidSky.pausesFrames(hour: hour, light: light, poseStill: false) {
                    if lift >= liquidStarMinLift {
                        for depth in steps {
                            for twinkle in steps {
                                XCTAssertLessThan(liquidStarOpacity(stars: stars, depth: depth, twinkle: twinkle),
                                                  liquidStarMinOpacity, "minute \(minute), light \(light)")
                            }
                        }
                    }
                } else {
                    XCTAssertGreaterThanOrEqual(liquidStarOpacity(stars: stars, depth: 1, twinkle: 1),
                                                liquidStarMinOpacity, "minute \(minute), light \(light)")
                    XCTAssertGreaterThanOrEqual(lift, liquidStarMinLift, "minute \(minute), light \(light)")
                }
            }
        }
    }
}
