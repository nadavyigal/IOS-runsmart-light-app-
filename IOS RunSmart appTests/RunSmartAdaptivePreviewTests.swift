import XCTest
@testable import IOS_RunSmart_app

final class RunSmartAdaptivePreviewTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testAppVariantReadsAdaptiveBuildSetting() {
        XCTAssertEqual(
            RunSmartAppVariant(infoDictionary: ["RUNSMART_APP_VARIANT": "adaptive"]),
            .adaptivePreview
        )
        XCTAssertEqual(
            RunSmartAppVariant(infoDictionary: ["RUNSMART_APP_VARIANT": "production"]),
            .production
        )
    }

    func testUnknownOrMissingAppVariantDefaultsToProduction() {
        XCTAssertEqual(RunSmartAppVariant(infoDictionary: [:]), .production)
        XCTAssertEqual(
            RunSmartAppVariant(infoDictionary: ["RUNSMART_APP_VARIANT": "unexpected"]),
            .production
        )
    }

    func testAdaptivePreviewAlwaysRequiresLocalDemoIsolation() {
        XCTAssertTrue(
            RunSmartBuildFlavor.requiresLocalDemoIsolation(for: .adaptivePreview)
        )
        XCTAssertFalse(
            RunSmartBuildFlavor.requiresLocalDemoIsolation(for: .production)
        )
    }

    func testAdaptiveFixtureAlwaysContainsARecentMissedWorkout() throws {
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 10))
        )
        let workouts = RunSmartAdaptivePreviewData.workouts(now: now, calendar: calendar)
        let missed = FlexWeekPresentation.mostRecentMissedWorkout(
            in: workouts,
            now: now,
            calendar: calendar
        )

        XCTAssertNotNil(missed)
        XCTAssertFalse(try XCTUnwrap(missed).isComplete)
        XCTAssertTrue(try XCTUnwrap(missed).scheduledDate < now)
    }

    func testAdaptiveEntryIsHiddenFromProductionBuild() {
        XCTAssertFalse(
            AdaptivePreviewPresentation.shouldShowCard(for: .production)
        )
        XCTAssertTrue(
            AdaptivePreviewPresentation.shouldShowCard(for: .adaptivePreview)
        )
    }

    func testAdaptiveEntryPreselectsTheMissedWorkout() throws {
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 10))
        )
        let workouts = RunSmartAdaptivePreviewData.workouts(now: now, calendar: calendar)
        let missed = try XCTUnwrap(
            FlexWeekPresentation.mostRecentMissedWorkout(
                in: workouts,
                now: now,
                calendar: calendar
            )
        )

        XCTAssertEqual(
            AdaptivePreviewPresentation.preselectedReason(
                in: workouts,
                now: now,
                calendar: calendar
            ),
            .missedWorkout(workoutID: missed.id)
        )
    }

    func testMissedWorkoutPreviewKeepsEveryWorkoutIdentityUnique() throws {
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 10))
        )
        let workouts = RunSmartAdaptivePreviewData.workouts(now: now, calendar: calendar)
        let missed = try XCTUnwrap(
            FlexWeekPresentation.mostRecentMissedWorkout(
                in: workouts,
                now: now,
                calendar: calendar
            )
        )
        let (updated, _) = DeterministicFlexWeekBuilder.restructure(
            week: workouts,
            reason: .missedWorkout(workoutID: missed.id),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(Set(updated.map(\.id)).count, updated.count)
    }
}
