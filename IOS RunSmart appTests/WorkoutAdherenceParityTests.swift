import XCTest
@testable import IOS_RunSmart_app

// C7.6 AC6: the Swift WorkoutAdherence and the SQL workout_adherence_state /
// workout_adherence_boundary (supabase/migrations/20261122120000_workout_adherence_state.sql)
// agree on one shared list of cases: supabase/tests/workout_adherence_fixtures.sql. The SQL test
// includes that file; this test reads the JSON between its $fixtures$ markers. Partial at 80%,
// rest, extra, and the 20:00 cutoff in several zones and across DST.

final class WorkoutAdherenceParityTests: XCTestCase {
    private struct Fixture: Decodable {
        let name: String
        let type: String?
        let plannedDistance: Double?
        let plannedDurationMinutes: Int?
        let scheduledDate: String?
        let runDistanceKm: Double?
        let runDurationSeconds: Int?
        let now: String
        let timeZone: String
        let boundary: String
        let state: String
    }

    private static var fixtureFile: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("supabase/tests/workout_adherence_fixtures.sql")
    }

    private func fixtures() throws -> [Fixture] {
        let text = try String(contentsOf: Self.fixtureFile, encoding: .utf8)
        // The one dollar-quoted block whose body is the JSON array.
        let blocks = text.components(separatedBy: "$fixtures$")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("[") && $0.hasSuffix("]") }
        XCTAssertEqual(blocks.count, 1, "expected one JSON block in workout_adherence_fixtures.sql")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([Fixture].self, from: Data(try XCTUnwrap(blocks.first).utf8))
    }

    func testSwiftMatchesTheSharedSQLFixtures() throws {
        let cases = try fixtures()
        XCTAssertGreaterThanOrEqual(cases.count, 15)
        let athlete = UUID()
        let workoutID = UUID()

        for fixture in cases {
            let zone = try XCTUnwrap(TimeZone(identifier: fixture.timeZone), fixture.name)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let now = try XCTUnwrap(ISO8601DateFormatter().date(from: fixture.now), fixture.name)
            let boundary = WorkoutAdherence.missedBoundary(now: now, calendar: calendar)
            XCTAssertEqual(boundary, fixture.boundary, "boundary: \(fixture.name)")

            let hasRun = fixture.runDistanceKm != nil || fixture.runDurationSeconds != nil
            var run: CoachRunSummary?
            if hasRun {
                run = try JSONDecoder().decode(CoachRunSummary.self, from: Data("""
                {"id":1,"athlete_id":"\(athlete)","workout_id":\(fixture.type == nil ? "null" : "\"\(workoutID)\""),
                "completed_at":"\(fixture.now)","distance_km":\(fixture.runDistanceKm ?? 0),
                "duration_seconds":\(fixture.runDurationSeconds ?? 0)}
                """.utf8))
            }

            let state: String
            if let type = fixture.type {
                let workout = try JSONDecoder().decode(CoachWorkoutSummary.self, from: Data("""
                {"id":"\(workoutID)","athlete_id":"\(athlete)","plan_id":"\(UUID())",
                "scheduled_date":"\(fixture.scheduledDate ?? "")","type":"\(type)",
                "planned_distance":\(fixture.plannedDistance ?? 0),
                "planned_duration_minutes":\(fixture.plannedDurationMinutes.map(String.init) ?? "null"),
                "completed":false}
                """.utf8))
                if !WorkoutAdherence.counts(workout) {
                    state = "rest"
                } else {
                    state = Self.name(WorkoutAdherence.classify(workout: workout, run: run, today: boundary))
                }
            } else {
                let extra = try XCTUnwrap(run, fixture.name)
                state = try Self.name(XCTUnwrap(WorkoutAdherence.classify(run: extra), fixture.name))
            }
            XCTAssertEqual(state, fixture.state, "state: \(fixture.name)")
        }
    }

    /// The SQL names (workout_adherence_state).
    private static func name(_ state: WorkoutAdherence) -> String {
        switch state {
        case .done: "done"
        case .partial: "partial"
        case .missed: "missed"
        case .planned: "planned"
        case .extra: "extra"
        }
    }
}
