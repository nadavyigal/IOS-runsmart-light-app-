import XCTest
@testable import IOS_RunSmart_app

/// Record-a-run S10: post-run summary helpers (title, notes, pace bars, elevation across pauses).
@MainActor
final class PostRunSummaryTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(hour: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: hour, minute: 30))!
    }

    private func makeRun(title: String? = nil, notes: String? = nil, hour: Int = 7) -> RecordedRun {
        RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: date(hour: hour),
            endedAt: date(hour: hour).addingTimeInterval(1_800),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_800,
            averagePaceSecondsPerKm: 360,
            averageHeartRateBPM: nil,
            routePoints: [],
            syncedAt: nil,
            title: title,
            notes: notes
        )
    }

    // MARK: Default title

    func testDefaultTitleFollowsTimeOfDay() {
        XCTAssertEqual(RunTitle.defaultTitle(startedAt: date(hour: 5), calendar: utc), "Morning Run")
        XCTAssertEqual(RunTitle.defaultTitle(startedAt: date(hour: 11), calendar: utc), "Morning Run")
        XCTAssertEqual(RunTitle.defaultTitle(startedAt: date(hour: 12), calendar: utc), "Afternoon Run")
        XCTAssertEqual(RunTitle.defaultTitle(startedAt: date(hour: 16), calendar: utc), "Afternoon Run")
        XCTAssertEqual(RunTitle.defaultTitle(startedAt: date(hour: 17), calendar: utc), "Evening Run")
        XCTAssertEqual(RunTitle.defaultTitle(startedAt: date(hour: 20), calendar: utc), "Evening Run")
        XCTAssertEqual(RunTitle.defaultTitle(startedAt: date(hour: 21), calendar: utc), "Night Run")
        XCTAssertEqual(RunTitle.defaultTitle(startedAt: date(hour: 2), calendar: utc), "Night Run")
    }

    func testPlannedWorkoutTitleBeatsTimeOfDay() {
        XCTAssertEqual(RunTitle.defaultTitle(startedAt: date(hour: 7), plannedTitle: "  Tempo 5 km ", calendar: utc), "Tempo 5 km")
        XCTAssertEqual(RunTitle.defaultTitle(startedAt: date(hour: 7), plannedTitle: "   ", calendar: utc), "Morning Run")
        XCTAssertEqual(RunTitle.defaultTitle(startedAt: date(hour: 7), plannedTitle: nil, calendar: utc), "Morning Run")
    }

    func testDisplayTitleUsesStoredTitleThenDefault() {
        XCTAssertEqual(RunTitle.displayTitle(for: makeRun(title: "Park loop"), calendar: utc), "Park loop")
        XCTAssertEqual(RunTitle.displayTitle(for: makeRun(title: nil, hour: 18), calendar: utc), "Evening Run")
    }

    func testUpdatedTitleKeepsStoredValueWhenUntouchedAndClearsWhenEmpty() {
        let planned = makeRun(title: "Tempo 5 km")
        XCTAssertEqual(RunTitle.updatedTitle(input: "Tempo 5 km", for: planned, calendar: utc), "Tempo 5 km")
        XCTAssertEqual(RunTitle.updatedTitle(input: "  Hill repeats ", for: planned, calendar: utc), "Hill repeats")
        XCTAssertNil(RunTitle.updatedTitle(input: "   ", for: planned, calendar: utc))

        let plain = makeRun(title: nil, hour: 7)
        XCTAssertNil(RunTitle.updatedTitle(input: "Morning Run", for: plain, calendar: utc), "an untouched default is not stored")
    }

    func testTitleAndNotesAreTrimmedAndLimited() {
        XCTAssertNil(RunTitle.updatedNotes(input: " \n "))
        XCTAssertEqual(RunTitle.updatedNotes(input: " felt good \n"), "felt good")
        let long = String(repeating: "a", count: RunTitle.maximumTitleLength + 20)
        XCTAssertEqual(RunTitle.normalized(long, limit: RunTitle.maximumTitleLength)?.count, RunTitle.maximumTitleLength)
    }

    // MARK: Codable back-compat

    func testRunWithoutTitleOrNotesStillDecodes() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(makeRun())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "title")
        json.removeValue(forKey: "notes")
        let oldData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try decoder.decode(RecordedRun.self, from: oldData)
        XCTAssertNil(decoded.title)
        XCTAssertNil(decoded.notes)
    }

    func testTitleAndNotesRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(RecordedRun.self, from: encoder.encode(makeRun(title: "Park loop", notes: "Windy")))
        XCTAssertEqual(decoded.title, "Park loop")
        XCTAssertEqual(decoded.notes, "Windy")
    }

    func testLocalStoreKeepsFieldsWrittenSinceTheCallerLoadedTheRun() {
        let store = RunSmartLocalStore.shared
        var stored = makeRun()
        stored.rpe = 6
        store.saveRun(stored)
        defer { store.removeRun(stored) }

        // A stale copy (no rpe) must not erase the stored rpe when title and notes are saved.
        let stale = makeRun()
        var staleCopy = stale
        staleCopy.id = stored.id
        let updated = store.updateRunDetails(staleCopy, title: "Park loop", notes: "Windy")

        XCTAssertEqual(updated.rpe, 6)
        let reloaded = store.loadRuns().first { $0.id == stored.id }
        XCTAssertEqual(reloaded?.title, "Park loop")
        XCTAssertEqual(reloaded?.notes, "Windy")
        XCTAssertEqual(reloaded?.rpe, 6)
    }

    // MARK: Pace bars

    func testBarFractionsRankFasterSplitsTaller() {
        let fractions = SplitPaceChart.barFractions(paces: [300, 330, 360])
        XCTAssertEqual(fractions[0], 1, accuracy: 0.0001)
        XCTAssertEqual(fractions[2], SplitPaceChart.slowestFraction, accuracy: 0.0001)
        XCTAssertGreaterThan(fractions[0], fractions[1])
        XCTAssertGreaterThan(fractions[1], fractions[2])
    }

    func testBarFractionsForEqualOrInvalidPaces() {
        XCTAssertEqual(SplitPaceChart.barFractions(paces: [320, 320]), [SplitPaceChart.uniformFraction, SplitPaceChart.uniformFraction])
        XCTAssertEqual(SplitPaceChart.barFractions(paces: [320]), [SplitPaceChart.uniformFraction])
        XCTAssertEqual(SplitPaceChart.barFractions(paces: [0, .nan, -1]), [0, 0, 0])
        XCTAssertEqual(SplitPaceChart.barFractions(paces: []), [])
        let mixed = SplitPaceChart.barFractions(paces: [0, 300, 360])
        XCTAssertEqual(mixed[0], 0)
        XCTAssertEqual(mixed[1], 1, accuracy: 0.0001)
    }

    // MARK: Elevation across pauses

    private func point(_ altitude: Double, startsNewSegment: Bool? = nil, second: TimeInterval) -> RunRoutePoint {
        RunRoutePoint(
            latitude: 32.08,
            longitude: 34.78,
            timestamp: Date(timeIntervalSince1970: 1_000 + second),
            horizontalAccuracy: 5,
            altitude: altitude,
            startsNewSegment: startsNewSegment
        )
    }

    func testAscentDoesNotCountAClimbAcrossASegmentStart() {
        let points = [
            point(10, second: 0),
            point(15, second: 10),
            // Paused, then resumed 40 m higher (elevator or car): not climbing.
            point(55, startsNewSegment: true, second: 600),
            point(58, second: 610)
        ]
        XCTAssertEqual(RunRoutePoint.ascentMeters(in: points), 8, accuracy: 0.001)
    }

    func testSavedRouteElevationGainSkipsPauseJumps() {
        var run = makeRun()
        run.routePoints = [
            point(10, second: 0),
            point(14, second: 10),
            point(80, startsNewSegment: true, second: 900),
            point(82, second: 910)
        ]
        let route = SavedRoute.from(run: run, name: "Loop")
        XCTAssertEqual(route.elevationGainMeters, 6)
    }
}
