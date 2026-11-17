import XCTest
@testable import IOS_RunSmart_app

final class CoachReadServiceTests: XCTestCase {
    func testLocalCalendarChoosesTheDateSentToTheServer() async throws {
        let client = RecordingClient()
        let service = CoachReadService(client: client)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 2 * 60 * 60)!
        let evening = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-15T22:30:00Z"))
        let athlete = UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000B")!

        _ = try await service.workouts(from: evening, to: evening, athleteIDs: [athlete], calendar: calendar)
        _ = try await service.runs(from: evening, to: evening, calendar: calendar)

        XCTAssertEqual(client.workoutQuery, CoachWorkoutQuery(from: "2026-11-16", to: "2026-11-16", athleteIDs: [athlete]))
        XCTAssertEqual(client.runQuery, CoachRunQuery(from: "2026-11-16", to: "2026-11-16", athleteIDs: nil))
    }

    func testNilAthleteFilterOmitsTheServerArgument() throws {
        let query = CoachWorkoutQuery(from: "2026-11-16", to: "2026-11-22", athleteIDs: nil)
        let json = try JSONEncoder().encode(query)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])

        XCTAssertEqual(object["p_from"] as? String, "2026-11-16")
        XCTAssertEqual(object["p_to"] as? String, "2026-11-22")
        XCTAssertNil(object["p_athlete_ids"])
    }

    func testRunSummaryCannotDecodeRouteOrNotes() throws {
        let keys = Set(CoachRunSummary.CodingKeys.allCases.map(\.stringValue))
        XCTAssertEqual(keys, [
            "id", "athlete_id", "workout_id", "completed_at", "type",
            "distance_km", "duration_seconds", "pace", "average_heart_rate", "source"
        ])
        XCTAssertFalse(keys.contains("route"))
        XCTAssertFalse(keys.contains("notes"))

        let payload = """
        {
          "id": 42,
          "athlete_id": "BBBBBBBB-0000-4000-8000-00000000000B",
          "workout_id": "30000000-0000-4000-8000-0000000000B1",
          "completed_at": "2026-11-16T00:30:00.000000+00:00",
          "type": "easy",
          "distance_km": 5.1,
          "duration_seconds": 1860,
          "pace": 364.7,
          "average_heart_rate": 142,
          "source": "runsmart_ios",
          "route": [{"lat": 32.0, "lng": 34.0}],
          "notes": "PRIVATE_RUN_NOTE"
        }
        """.data(using: .utf8)!
        let run = try JSONDecoder().decode(CoachRunSummary.self, from: payload)
        let encoded = try JSONEncoder().encode(run)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(run.id, 42)
        XCTAssertEqual(run.distanceKm, 5.1)
        XCTAssertEqual(run.pace, 364.7)
        XCTAssertEqual(run.source, "runsmart_ios")
        XCTAssertNil(object["route"])
        XCTAssertNil(object["notes"])
        XCTAssertEqual(keys, Set(object.keys))
    }

    func testWorkoutSummaryKeepsNotesAndDropsAnythingElse() throws {
        let keys = Set(CoachWorkoutSummary.CodingKeys.allCases.map(\.stringValue))
        XCTAssertTrue(keys.contains("notes"))
        XCTAssertFalse(keys.contains("route"))

        let payload = """
        {
          "id": "30000000-0000-4000-8000-0000000000B1",
          "athlete_id": "BBBBBBBB-0000-4000-8000-00000000000B",
          "plan_id": "10000000-0000-4000-8000-0000000000B1",
          "scheduled_date": "2026-11-16",
          "type": "easy",
          "planned_distance": 5,
          "planned_duration_minutes": 30,
          "target_pace": 360,
          "completed": true,
          "completed_at": "2026-11-16 06:00:00+00",
          "actual_distance_km": 5.1,
          "actual_duration_minutes": 31,
          "actual_pace": 365,
          "notes": "Easy day",
          "route": "nope"
        }
        """.data(using: .utf8)!
        let workout = try JSONDecoder().decode(CoachWorkoutSummary.self, from: payload)
        XCTAssertEqual(workout.notes, "Easy day")
        XCTAssertEqual(workout.scheduledDate, "2026-11-16")
        XCTAssertEqual(workout.actualPace, 365)
        XCTAssertEqual(workout.completedAt, try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-16T06:00:00Z")))
    }

    func testAthleteSummaryUsesProfileNameAndConsentTime() throws {
        let payload = """
        {
          "athlete_id": "BBBBBBBB-0000-4000-8000-00000000000B",
          "display_name": "Yoni Cohen",
          "linked_at": "2026-11-17T08:00:00+00:00",
          "has_active_plan": true
        }
        """.data(using: .utf8)!
        let athlete = try JSONDecoder().decode(CoachAthleteSummary.self, from: payload)
        XCTAssertEqual(athlete.displayName, "Yoni Cohen")
        XCTAssertTrue(athlete.hasActivePlan)
        XCTAssertEqual(athlete.linkedAt, try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-17T08:00:00Z")))
    }

    func testMockReturnsOnlyTheRowsItWasGiven() async throws {
        let athleteID = UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000B")!
        let linkedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-17T08:00:00Z"))
        let mock = MockCoachReadService(
            athletes: [CoachAthleteSummary(athleteID: athleteID, displayName: "Yoni Cohen", linkedAt: linkedAt, hasActivePlan: false)],
            plans: [athleteID: []],
            workoutResults: [],
            runResults: []
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let athletes = try await mock.listAthletes()
        let plans = try await mock.plan(for: athleteID)
        let workouts = try await mock.workouts(from: linkedAt, to: linkedAt, athleteIDs: nil, calendar: calendar)

        XCTAssertEqual(athletes.map(\.displayName), ["Yoni Cohen"])
        XCTAssertFalse(athletes[0].hasActivePlan)
        XCTAssertTrue(plans.isEmpty)
        XCTAssertTrue(workouts.isEmpty)
    }

    func testRPCNamesMatchTheMigration() {
        XCTAssertEqual(CoachReadRPC.listAthletes, "coach_list_athletes")
        XCTAssertEqual(CoachReadRPC.plan, "coach_get_athlete_plan")
        XCTAssertEqual(CoachReadRPC.workouts, "coach_get_athletes_workouts")
        XCTAssertEqual(CoachReadRPC.runs, "coach_get_athletes_runs")
    }
}

private final class RecordingClient: CoachReadFetching, @unchecked Sendable {
    var workoutQuery: CoachWorkoutQuery?
    var runQuery: CoachRunQuery?

    func listAthletes() async throws -> [CoachAthleteSummary] { [] }
    func plans(for athleteID: UUID) async throws -> [CoachPlanSummary] { [] }

    func workouts(_ query: CoachWorkoutQuery) async throws -> [CoachWorkoutSummary] {
        workoutQuery = query
        return []
    }

    func runs(_ query: CoachRunQuery) async throws -> [CoachRunSummary] {
        runQuery = query
        return []
    }
}
