import XCTest
@testable import IOS_RunSmart_app

/// C7.3 AC4: the coach's day detail shows "Effort 7/10" and the athlete's quoted note, and nothing
/// when Coach v2 is off, effort is not shared, or there is no readable note.
@MainActor
final class CoachDaySharingTests: XCTestCase {
    private let athlete = UUID()
    private let now = ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z")!

    private func run(_ id: Int, on day: String = "2026-11-16", rpe: Int? = nil, hasNote: Bool = false) throws -> CoachRunSummary {
        try JSONDecoder().decode(CoachRunSummary.self, from: Data("""
        {"id":\(id),"athlete_id":"\(athlete)","workout_id":null,
        "completed_at":"\(day)T07:00:00Z","distance_km":5,"duration_seconds":1650,
        "rpe":\(rpe.map(String.init) ?? "null"),"has_note":\(hasNote)}
        """.utf8))
    }

    private func plain(_ text: String?) -> String? {
        text?.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(of: "\u{2069}", with: "")
    }

    private func sharing(_ notes: [Int: String] = [:], name: String = "Yoni") -> CoachDaySharing {
        CoachDaySharing(athleteName: name, notes: notes)
    }

    // MARK: Lines

    func testEffortAndQuotedNoteWithAttribution() throws {
        let lines = CoachRunSharingLines(run: try run(1, rpe: 7, hasNote: true), sharing: sharing([1: "Legs felt heavy"]))
        XCTAssertEqual(lines.effort, "Effort 7/10")
        XCTAssertEqual(lines.spokenEffort, "Effort, 7 of 10")
        XCTAssertEqual(lines.note, "\u{201C}Legs felt heavy\u{201D}")
        XCTAssertEqual(plain(lines.attribution), "\u{2014} Yoni")
        XCTAssertEqual(lines.spokenNote, "Note from Yoni: Legs felt heavy")
        XCTAssertFalse(lines.isEmpty)
    }

    func testFlagOffShowsNothingEvenWithEffortAndNote() throws {
        let lines = CoachRunSharingLines(run: try run(1, rpe: 7, hasNote: true), sharing: nil)
        XCTAssertTrue(lines.isEmpty)
        XCTAssertNil(lines.effort)
        XCTAssertNil(lines.note)
        XCTAssertNil(lines.attribution)
    }

    func testNullRPEShowsNoEffort() throws {
        let lines = CoachRunSharingLines(run: try run(1, rpe: nil), sharing: sharing())
        XCTAssertNil(lines.effort)
        XCTAssertTrue(lines.isEmpty)
    }

    func testOutOfRangeRPEShowsNoEffort() throws {
        XCTAssertNil(CoachRunSharingLines(run: try run(1, rpe: 0), sharing: sharing()).effort)
        XCTAssertNil(CoachRunSharingLines(run: try run(2, rpe: 11), sharing: sharing()).effort)
    }

    func testHasNoteFalseShowsNoNoteEvenIfOneWasLoaded() throws {
        // A hidden note comes back as has_note false: nothing shows, and there is no "hidden" line.
        let lines = CoachRunSharingLines(run: try run(1, rpe: 6, hasNote: false), sharing: sharing([1: "old note"]))
        XCTAssertEqual(lines.effort, "Effort 6/10")
        XCTAssertNil(lines.note)
        XCTAssertNil(lines.attribution)
    }

    func testHasNoteWithoutReadableNoteShowsNothing() throws {
        // The server dropped the id (hidden since, or link ended) or the read failed.
        XCTAssertTrue(CoachRunSharingLines(run: try run(1, hasNote: true), sharing: sharing()).isEmpty)
        XCTAssertTrue(CoachRunSharingLines(run: try run(2, hasNote: true), sharing: sharing([2: "  \n "])).isEmpty)
    }

    func testNoteOnlyWithoutEffort() throws {
        let lines = CoachRunSharingLines(run: try run(1, hasNote: true), sharing: sharing([1: "Windy"]))
        XCTAssertNil(lines.effort)
        XCTAssertEqual(lines.note, "\u{201C}Windy\u{201D}")
    }

    func testHebrewNoteKeepsItsDirectionAndTheNameIsIsolated() throws {
        let lines = CoachRunSharingLines(
            run: try run(1, rpe: 8, hasNote: true), sharing: sharing([1: "הרגליים היו כבדות"], name: "יוני")
        )
        let note = try XCTUnwrap(lines.note)
        XCTAssertEqual(BidiText.paragraphDirection(note), .rightToLeft, "the quote marks do not decide the direction")
        XCTAssertEqual(lines.attribution, "\u{2014} \u{2068}יוני\u{2069}")
        let english = CoachRunSharingLines(run: try run(2, hasNote: true), sharing: sharing([2: "5k felt easy"]))
        XCTAssertEqual(BidiText.paragraphDirection(try XCTUnwrap(english.note)), .leftToRight)
    }

    // MARK: Model

    private actor NotesSpy {
        private(set) var calls: [[Int]] = []
        var result: Result<[Int: String], Error>

        init(_ result: Result<[Int: String], Error>) { self.result = result }

        func fetch(_ ids: [Int]) throws -> [Int: String] {
            calls.append(ids)
            return try result.get()
        }

        func set(_ result: Result<[Int: String], Error>) { self.result = result }
    }

    private func service(runs: [CoachRunSummary]) -> MockCoachReadService {
        var service = MockCoachReadService()
        service.athletes = [CoachAthleteSummary(athleteID: athlete, displayName: "Yoni", linkedAt: now, hasActivePlan: true)]
        service.runResults = runs
        return service
    }

    private func load(_ model: CoachAthleteDetailModel) async {
        await model.load(now: now, locale: Locale(identifier: "en_US"), timeZone: .gmt)
    }

    func testFlagOffNeverReadsNotes() async throws {
        let spy = NotesSpy(.success([1: "note"]))
        let model = CoachAthleteDetailModel(
            athleteID: athlete, service: service(runs: [try run(1, rpe: 7, hasNote: true)]), coachV2: false,
            fetchNotes: { try await spy.fetch($0) }
        )
        await load(model)
        XCTAssertNotNil(model.current)
        XCTAssertTrue(model.runNotes.isEmpty)
        let calls = await spy.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testFlagOnReadsOnlyRunsWithNotes() async throws {
        let spy = NotesSpy(.success([1: "Legs felt heavy"]))
        let runs = [try run(1, rpe: 7, hasNote: true), try run(2, on: "2026-11-17", rpe: 5), try run(3, on: "2026-11-10", hasNote: true)]
        let model = CoachAthleteDetailModel(
            athleteID: athlete, service: service(runs: runs), coachV2: true, fetchNotes: { try await spy.fetch($0) }
        )
        await load(model)
        XCTAssertEqual(model.runNotes, [1: "Legs felt heavy"])
        let calls = await spy.calls
        XCTAssertEqual(calls.map { $0.sorted() }, [[1, 3]])
    }

    func testFlagOnWithNoNotesSkipsTheRead() async throws {
        let spy = NotesSpy(.success([:]))
        let model = CoachAthleteDetailModel(
            athleteID: athlete, service: service(runs: [try run(1, rpe: 7)]), coachV2: true,
            fetchNotes: { try await spy.fetch($0) }
        )
        await load(model)
        let calls = await spy.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testFailedNoteReadKeepsTheWeekAndTheLastGoodNotes() async throws {
        let spy = NotesSpy(.success([1: "first"]))
        let model = CoachAthleteDetailModel(
            athleteID: athlete, service: service(runs: [try run(1, rpe: 7, hasNote: true)]), coachV2: true,
            fetchNotes: { try await spy.fetch($0) }
        )
        await load(model)
        XCTAssertEqual(model.runNotes, [1: "first"])

        await spy.set(.failure(URLError(.timedOut)))
        await load(model)
        XCTAssertFalse(model.failure, "a note read never fails the week")
        XCTAssertNotNil(model.current)
        XCTAssertEqual(model.runNotes, [1: "first"])
    }

    func testFailedFirstNoteReadShowsNoNote() async throws {
        let spy = NotesSpy(.failure(URLError(.notConnectedToInternet)))
        let model = CoachAthleteDetailModel(
            athleteID: athlete, service: service(runs: [try run(1, rpe: 7, hasNote: true)]), coachV2: true,
            fetchNotes: { try await spy.fetch($0) }
        )
        await load(model)
        XCTAssertFalse(model.failure)
        XCTAssertTrue(model.runNotes.isEmpty)
    }
}
