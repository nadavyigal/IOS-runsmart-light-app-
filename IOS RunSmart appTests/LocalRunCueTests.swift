import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class LocalRunCueTests: XCTestCase {
    func testEachKilometerOnceAndIntervalPaceSkipsPauseTime() {
        var cues = RunCueSchedule()
        cues.reset(distance: 0, movingTime: 0)
        XCTAssertNil(cues.update(distance: 999, movingTime: 299, settings: .init()))
        let first = cues.update(distance: 1_000, movingTime: 300, settings: .init())
        XCTAssertTrue(first?.contains("1 kilometer") == true)
        XCTAssertTrue(first?.contains("5 minutes") == true)
        XCTAssertNil(cues.update(distance: 1_000, movingTime: 300, settings: .init()))
        let second = cues.update(distance: 2_000, movingTime: 600, settings: .init())
        XCTAssertTrue(second?.contains("Split pace 5 minutes") == true)
    }

    func testHalfKilometerAndTimeCadence() {
        var cues = RunCueSchedule()
        var settings = RunCueSettings()
        settings.cadence = .halfKilometer
        XCTAssertNotNil(cues.update(distance: 500, movingTime: 160, settings: settings))
        XCTAssertNil(cues.update(distance: 500, movingTime: 160, settings: settings))
        settings.cadence = .fiveMinutes
        cues.reset(distance: 0, movingTime: 0)
        XCTAssertNil(cues.update(distance: 900, movingTime: 299, settings: settings))
        XCTAssertNotNil(cues.update(distance: 900, movingTime: 300, settings: settings))
        XCTAssertNil(cues.update(distance: 900, movingTime: 300, settings: settings))
    }

    func testRecoveredRunDoesNotReplayHistoricalCues() {
        var cues = RunCueSchedule()
        cues.reset(distance: 5_200, movingTime: 1_600)
        XCTAssertNil(cues.update(distance: 5_210, movingTime: 1_603, settings: .init()))
        XCTAssertNotNil(cues.update(distance: 6_000, movingTime: 1_840, settings: .init()))
    }

    func testDisabledCueAdvancesBaselineAndMetricsCanBeOmitted() {
        var cues = RunCueSchedule()
        var settings = RunCueSettings()
        settings.enabled = false
        XCTAssertNil(cues.update(distance: 1_000, movingTime: 300, settings: settings))
        settings.enabled = true
        XCTAssertNil(cues.update(distance: 1_001, movingTime: 301, settings: settings))
        settings.distance = false
        settings.pace = false
        let text = cues.update(distance: 2_000, movingTime: 600, settings: settings)
        XCTAssertFalse(text?.contains("kilometer") == true)
        XCTAssertTrue(text?.contains("Moving time") == true)
    }

    func testOvershootingFixUsesExactMilestoneAndInterpolatedPace() {
        var cues = RunCueSchedule()
        XCTAssertNil(cues.update(distance: 990, movingTime: 297, settings: .init()))
        let text = cues.update(distance: 1_020, movingTime: 306, settings: .init())
        XCTAssertTrue(text?.hasPrefix("1 kilometer.") == true)
        XCTAssertTrue(text?.contains("Split pace 5 minutes 0 seconds") == true)
        XCTAssertTrue(text?.contains("Moving time 5 minutes 0 seconds") == true)
    }

    func testAutoPauseRollbackDoesNotRepeatMovingTimeMilestone() {
        var cues = RunCueSchedule()
        var settings = RunCueSettings()
        settings.cadence = .fiveMinutes
        cues.reset(distance: 0, movingTime: 0)
        XCTAssertNil(cues.update(distance: 900, movingTime: 299, settings: settings))
        XCTAssertNotNil(cues.update(distance: 900, movingTime: 300, settings: settings))
        XCTAssertNil(cues.update(distance: 900, movingTime: 292, settings: settings))
        XCTAssertNil(cues.update(distance: 900, movingTime: 300, settings: settings))
    }

    func testPreferencesRoundTripAndDefaultOfflineCuesOn() throws {
        let suite = "cue-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(RunCueSettings.load(from: defaults).enabled)
        var settings = RunCueSettings()
        settings.cadence = .halfKilometer
        settings.pace = false
        settings.save(to: defaults)
        XCTAssertEqual(RunCueSettings.load(from: defaults), settings)
    }
}
