import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class WorkoutAdherenceTests: XCTestCase {
    private let athlete = UUID()
    private let workoutID = UUID()
    private let now = ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z")!

    private func workout(date: String = "2026-11-17", distance: Double = 10) throws -> CoachWorkoutSummary {
        try JSONDecoder().decode(CoachWorkoutSummary.self, from: Data("""
        {"id":"\(workoutID)","athlete_id":"\(athlete)","plan_id":"\(UUID())",
        "scheduled_date":"\(date)","type":"easy","planned_distance":\(distance),
        "planned_duration_minutes":50,"completed":true}
        """.utf8))
    }

    private func run(distance: Double = 8, seconds: Int = 2400, linked: Bool = true) throws -> CoachRunSummary {
        try JSONDecoder().decode(CoachRunSummary.self, from: Data("""
        {"id":1,"athlete_id":"\(athlete)","workout_id":\(linked ? "\"\(workoutID)\"" : "null"),
        "completed_at":"2026-11-17T12:00:00Z","distance_km":\(distance),"duration_seconds":\(seconds)}
        """.utf8))
    }

    func testThresholdAndDistanceTakesPrecedence() throws {
        let planned = try workout()
        let today = "2026-11-18"
        XCTAssertEqual(try WorkoutAdherence.classify(workout: planned, run: run(distance: 7.99), today: today), .partial)
        XCTAssertEqual(try WorkoutAdherence.classify(workout: planned, run: run(seconds: 1), today: today), .done)
        XCTAssertEqual(try WorkoutAdherence.classify(workout: workout(distance: 0), run: run(seconds: 2399), today: today), .partial)
        XCTAssertEqual(try WorkoutAdherence.classify(workout: workout(distance: 0), run: run(), today: today), .done)
    }

    func testOnlyLinkedRunsCountAndTodayIsNotMissed() throws {
        let today = "2026-11-18"
        let extra = try run(linked: false)
        XCTAssertEqual(WorkoutAdherence.classify(run: extra), .extra)
        XCTAssertEqual(try WorkoutAdherence.classify(workout: workout(), run: extra, today: today), .missed)
        XCTAssertEqual(try WorkoutAdherence.classify(workout: workout(date: today), run: nil, today: today), .planned)
        XCTAssertTrue(WorkoutAdherence.isBehind([("2026-11-17", .missed)], today: today))
        XCTAssertFalse(WorkoutAdherence.isBehind([("2026-11-17", .partial), ("2026-11-16", .missed)], today: today))
    }

    func testWeekStartsAndListGrouping() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let israel = CoachAthleteWeek(now: now, locale: Locale(identifier: "he_IL"), timeZone: zone)
        let elsewhere = CoachAthleteWeek(now: now, locale: Locale(identifier: "en_US"), timeZone: zone)
        XCTAssertEqual(CoachReadDay.iso(israel.interval.start, calendar: israel.calendar), "2026-11-15")
        XCTAssertEqual(CoachReadDay.iso(elsewhere.interval.start, calendar: elsewhere.calendar), "2026-11-16")
        let runner = CoachAthleteSummary(athleteID: athlete, displayName: "Dana", linkedAt: now, hasActivePlan: true)
        let joining = CoachAthleteSummary(athleteID: UUID(), displayName: "Neta", linkedAt: now, hasActivePlan: false)
        let args = try [workout()]
        let rows = try CoachAthleteRow.make(
            athletes: [joining, runner], workouts: args, runs: [run(distance: 7), run()],
            latest: [:], now: now, week: elsewhere
        )
        XCTAssertEqual(rows.map(\.status), [.onTrack, .joining])
        XCTAssertEqual(rows.first?.done, 1)
        XCTAssertEqual(rows.first?.planned, 1)
    }
}
