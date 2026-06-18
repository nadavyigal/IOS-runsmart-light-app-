import XCTest
@testable import IOS_RunSmart_app

final class AhaMomentsTests: XCTestCase {

    // MARK: - UserInsightService

    func testIdentityFirstTimerForGettingStarted() {
        let identity = UserInsightService.getRunningIdentity(
            goal: "First 5K",
            experience: "Getting started",
            paceMinPerKm: nil
        )
        XCTAssertEqual(identity.kind, .firstTimer)
    }

    func testIdentitySpeedSeekerForPRGoal() {
        let identity = UserInsightService.getRunningIdentity(
            goal: "10K PR",
            experience: "Race focused",
            paceMinPerKm: 6.0
        )
        XCTAssertEqual(identity.kind, .speedSeeker)
    }

    func testIdentityEnduranceBuilderForDistanceGoalAndSlowPace() {
        let identity = UserInsightService.getRunningIdentity(
            goal: "Half Marathon",
            experience: "Consistent runner",
            paceMinPerKm: 7.5
        )
        XCTAssertEqual(identity.kind, .enduranceBuilder)
    }

    func testGoalTimelineClampsToMinimumFourWeeks() {
        let timeline = UserInsightService.projectGoalTimeline(
            goal: "Just Run More",
            experience: "Race focused"
        )
        XCTAssertGreaterThanOrEqual(timeline.weeks, 4)
        XCTAssertLessThanOrEqual(timeline.weeks, 24)
        XCTAssertEqual(timeline.milestoneWeek, max(1, timeline.weeks / 2))
    }

    func testGoalTimelineUsesRepresentative5KBeginnerWeeks() {
        let timeline = UserInsightService.projectGoalTimeline(
            goal: "First 5K",
            experience: "Getting started"
        )
        XCTAssertEqual(timeline.weeks, 8)
    }

    // MARK: - AchievementDetector

    func testAchievementDetectsFirstRun() {
        let run = makeRun(distanceKm: 4.1)
        let result = AchievementDetector.detect(currentRun: run, priorRuns: [])
        guard case .firstRun(let distanceKm) = result else {
            return XCTFail("Expected first run achievement")
        }
        XCTAssertEqual(distanceKm, 4.1, accuracy: 0.001)
    }

    func testAchievementDetectsShowedUpForShortFirstRun() {
        let run = makeRun(distanceKm: 0.2)
        let result = AchievementDetector.detect(currentRun: run, priorRuns: [])
        XCTAssertEqual(result, .showedUp)
    }

    func testAchievementDetectsPersonalBest() {
        let prior = makeRun(id: UUID(), distanceKm: 3.0)
        let current = makeRun(id: UUID(), distanceKm: 4.2)
        let result = AchievementDetector.detect(currentRun: current, priorRuns: [prior])
        guard case .personalBest(let distanceKm, let previousBestKm) = result else {
            return XCTFail("Expected personal best achievement")
        }
        XCTAssertEqual(distanceKm, 4.2, accuracy: 0.001)
        XCTAssertEqual(previousBestKm, 3.0, accuracy: 0.001)
    }

    func testAchievementDoesNotFireWhenNotImproved() {
        let prior = makeRun(id: UUID(), distanceKm: 5.0)
        let current = makeRun(id: UUID(), distanceKm: 4.0)
        XCTAssertNil(AchievementDetector.detect(currentRun: current, priorRuns: [prior]))
    }

    // MARK: - ContextDetector

    func testContextDetectsSevenDayStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let runs = (0..<7).map { offset in
            makeRun(
                id: UUID(),
                distanceKm: 5,
                startedAt: calendar.date(byAdding: .day, value: -offset, to: today)!
            )
        }
        let current = runs[0]
        let result = ContextDetector.detect(
            currentRun: current,
            allRuns: runs,
            noticedOnCooldown: false
        )
        guard case .streak(let days) = result else {
            return XCTFail("Expected streak context")
        }
        XCTAssertEqual(days, 7)
    }

    func testContextRespectsNoticedCooldown() {
        let run = makeRun(distanceKm: 5)
        XCTAssertNil(
            ContextDetector.detect(
                currentRun: run,
                allRuns: [run],
                noticedOnCooldown: true
            )
        )
    }

    func testContextDetectsThirdRunWeek() {
        let calendar = Calendar.current
        var weekComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        weekComponents.hour = 12
        weekComponents.minute = 0
        weekComponents.second = 0
        let weekStart = calendar.date(from: weekComponents)!
        // Space runs across the week so streak (3 consecutive days) does not win priority.
        let runs = [
            makeRun(id: UUID(), distanceKm: 4, startedAt: weekStart),
            makeRun(id: UUID(), distanceKm: 4, startedAt: calendar.date(byAdding: .day, value: 2, to: weekStart)!),
            makeRun(id: UUID(), distanceKm: 4, startedAt: calendar.date(byAdding: .day, value: 4, to: weekStart)!)
        ]
        let result = ContextDetector.detect(
            currentRun: runs[2],
            allRuns: runs,
            noticedOnCooldown: false
        )
        XCTAssertEqual(result, .thirdRunWeek)
    }

    func testComputeStreakCountsConsecutiveDays() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dates = (0..<3).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        XCTAssertEqual(ContextDetector.computeStreak(runDates: dates, calendar: calendar, now: today), 3)
    }

    // MARK: - Helpers

    private func makeRun(
        id: UUID = UUID(),
        distanceKm: Double,
        startedAt: Date = Date()
    ) -> RecordedRun {
        RecordedRun(
            id: id,
            providerActivityID: nil,
            source: .runSmart,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            distanceMeters: distanceKm * 1_000,
            movingTimeSeconds: 1_800,
            averagePaceSecondsPerKm: 360,
            averageHeartRateBPM: nil,
            routePoints: [],
            routeMatchResult: nil,
            syncedAt: nil
        )
    }
}
