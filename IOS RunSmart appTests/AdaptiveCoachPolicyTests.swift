import XCTest
@testable import IOS_RunSmart_app

final class AdaptiveCoachPolicyTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = ISO8601DateFormatter().date(from: "2026-07-18T08:00:00Z")!

    private func workout(daysAgo: Int, complete: Bool) -> PlannedWorkout {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return PlannedWorkout(
            id: UUID(),
            scheduledDate: date,
            weekday: "MON",
            date: "1",
            kind: .tempo,
            title: "Tempo Run",
            distance: "8.0 km",
            detail: "",
            isToday: daysAgo == 0,
            isComplete: complete
        )
    }

    private let optimalLoad = TrainingLoadMetrics(acuteLoad: 900, chronicLoad: 900, acwr: 1.0, status: .optimal)
    private let spikedLoad = TrainingLoadMetrics(acuteLoad: 1800, chronicLoad: 1000, acwr: 1.8, status: .highRisk)
    private let insufficientLoad = TrainingLoadMetrics(acuteLoad: 0, chronicLoad: 0, acwr: nil, status: .insufficientData)

    func testMissedWorkoutWins() {
        let missed = workout(daysAgo: 1, complete: false)
        let prompt = AdaptiveCoachPolicy.prompt(
            weekWorkouts: [missed, workout(daysAgo: 0, complete: false)],
            readiness: 80,
            loadMetrics: spikedLoad,
            lastDismissedAt: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(prompt?.trigger, .missedWorkout)
        XCTAssertEqual(prompt?.reason, .missedWorkout(workoutID: missed.id))
    }

    func testLoadSpikeTriggersTiredReshape() {
        let prompt = AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 0, complete: false)],
            readiness: 80,
            loadMetrics: spikedLoad,
            lastDismissedAt: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(prompt?.trigger, .loadSpike)
        XCTAssertEqual(prompt?.reason, .tired)
    }

    func testLowRecoveryTriggersTiredReshape() {
        let prompt = AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 0, complete: false)],
            readiness: 38,
            loadMetrics: optimalLoad,
            lastDismissedAt: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(prompt?.trigger, .lowRecovery)
        XCTAssertEqual(prompt?.reason, .tired)
    }

    func testHealthySignalsProduceNoPrompt() {
        XCTAssertNil(AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 0, complete: false)],
            readiness: 72,
            loadMetrics: optimalLoad,
            lastDismissedAt: nil,
            now: now,
            calendar: calendar
        ))
    }

    func testReadinessBetween45And60IsPassiveLinkTerritoryNotProactive() {
        // The existing passive Flex Week link (readiness < 60) must stay the
        // only surface in this band; the proactive card is stricter (< 45).
        XCTAssertNil(AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 0, complete: false)],
            readiness: 52,
            loadMetrics: optimalLoad,
            lastDismissedAt: nil,
            now: now,
            calendar: calendar
        ))
    }

    func testDismissalSuppressesFor24Hours() {
        let dismissed = calendar.date(byAdding: .hour, value: -3, to: now)!
        XCTAssertNil(AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 1, complete: false)],
            readiness: 80,
            loadMetrics: optimalLoad,
            lastDismissedAt: dismissed,
            now: now,
            calendar: calendar
        ))
    }

    func testDismissalExpiresAfter24Hours() {
        let dismissed = calendar.date(byAdding: .hour, value: -25, to: now)!
        XCTAssertNotNil(AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 1, complete: false)],
            readiness: 80,
            loadMetrics: optimalLoad,
            lastDismissedAt: dismissed,
            now: now,
            calendar: calendar
        ))
    }

    func testInsufficientLoadDataNeverTriggersLoadSpike() {
        XCTAssertNil(AdaptiveCoachPolicy.prompt(
            weekWorkouts: [workout(daysAgo: 0, complete: false)],
            readiness: 80,
            loadMetrics: insufficientLoad,
            lastDismissedAt: nil,
            now: now,
            calendar: calendar
        ))
    }

    func testCardVisibilityRequiresFlagAndPrompt() {
        let prompt = AdaptiveCoachPrompt(
            trigger: .missedWorkout,
            headline: "Missed Tempo Run?",
            detail: "detail",
            reason: .tired
        )
        XCTAssertFalse(AdaptiveCoachPresentation.shouldShow(flagEnabled: false, prompt: prompt))
        XCTAssertTrue(AdaptiveCoachPresentation.shouldShow(flagEnabled: true, prompt: prompt))
        XCTAssertFalse(AdaptiveCoachPresentation.shouldShow(flagEnabled: true, prompt: nil))
    }
}
