import XCTest
@testable import IOS_RunSmart_app

final class CoachAthleteNamesTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let en = Locale(identifier: "en_US")

    private func athlete(_ name: String, _ iso: String, id: String) -> CoachAthleteSummary {
        CoachAthleteSummary(
            athleteID: UUID(uuidString: id)!, displayName: name,
            linkedAt: ISO8601DateFormatter().date(from: iso)!, hasActivePlan: true
        )
    }

    private func labels(_ athletes: [CoachAthleteSummary]) -> [String] {
        CoachAthleteNames.labeled(athletes, locale: en, timeZone: utc).map(\.displayName)
    }

    func testNamedAthleteKeepsName() {
        XCTAssertEqual(labels([athlete("Noa", "2026-11-20T08:00:00Z", id: "00000000-0000-4000-8000-000000000001")]), ["Noa"])
    }

    func testUnnamedAthletesGetJoinDate() {
        let result = labels([
            athlete("Athlete", "2026-11-20T08:00:00Z", id: "00000000-0000-4000-8000-000000000001"),
            athlete("Athlete", "2026-11-26T08:00:00Z", id: "00000000-0000-4000-8000-000000000002"),
        ])
        XCTAssertEqual(result, ["Athlete · joined Nov 20", "Athlete · joined Nov 26"])
        XCTAssertNotEqual(result[0], result[1])
    }

    func testSameDayUnnamedAreNumberedInLinkOrder() {
        let result = labels([
            athlete("Athlete", "2026-11-26T09:00:00Z", id: "00000000-0000-4000-8000-000000000002"),
            athlete("Athlete", "2026-11-26T08:00:00Z", id: "00000000-0000-4000-8000-000000000001"),
        ])
        XCTAssertEqual(result, ["Athlete · joined Nov 26 · 2", "Athlete · joined Nov 26"])
    }

    func testLegacyPlaceholderAndBlankCountAsUnnamed() {
        let result = labels([
            athlete("RunSmart Runner", "2026-11-20T08:00:00Z", id: "00000000-0000-4000-8000-000000000001"),
            athlete("  ", "2026-11-21T08:00:00Z", id: "00000000-0000-4000-8000-000000000002"),
        ])
        XCTAssertEqual(result, ["Athlete · joined Nov 20", "Athlete · joined Nov 21"])
    }

    func testDuplicateRealNamesAreNumbered() {
        let result = labels([
            athlete("Dana", "2026-11-20T08:00:00Z", id: "00000000-0000-4000-8000-000000000001"),
            athlete("dana", "2026-11-22T08:00:00Z", id: "00000000-0000-4000-8000-000000000002"),
        ])
        XCTAssertEqual(result, ["Dana", "dana · 2"])
    }

    func testHebrewNameIsKeptAndIsolatedInCopy() {
        XCTAssertEqual(labels([athlete(" נועה ", "2026-11-20T08:00:00Z", id: "00000000-0000-4000-8000-000000000001")]), ["נועה"])
        XCTAssertEqual(CoachAthleteUpdateCopy.needsUpdate("נועה"),
                       "Effort, notes and flags aren't available. \u{2068}נועה\u{2069} needs the latest RunSmart.")
    }

    func testUnnamedMonogramStaysA() {
        XCTAssertEqual(LeaveCoachCopy.monogram(for: "Athlete · joined Nov 26"), "A")
        XCTAssertEqual(LeaveCoachCopy.monogram(for: "Noa Levi"), "NL")
    }

    func testServiceLabelsTheRoster() async throws {
        struct Client: CoachReadFetching {
            let athletes: [CoachAthleteSummary]
            func listAthletes() async throws -> [CoachAthleteSummary] { athletes }
            func plans(for athleteID: UUID) async throws -> [CoachPlanSummary] { [] }
            func workouts(_ query: CoachWorkoutQuery) async throws -> [CoachWorkoutSummary] { [] }
            func runs(_ query: CoachRunQuery) async throws -> [CoachRunSummary] { [] }
        }
        let roster = [
            athlete("Athlete", "2026-11-20T08:00:00Z", id: "00000000-0000-4000-8000-000000000001"),
            athlete("Athlete", "2026-11-21T08:00:00Z", id: "00000000-0000-4000-8000-000000000002"),
        ]
        let names = try await CoachReadService(client: Client(athletes: roster)).listAthletes().map(\.displayName)
        XCTAssertEqual(Set(names).count, 2)
        XCTAssertTrue(names.allSatisfy(CoachAthleteNames.isUnnamedLabel))
    }

    // MARK: Coach's own name

    func testCoachNameRules() {
        XCTAssertEqual(CoachDisplayName.forSaving("  Dana Levi "), "Dana Levi")
        XCTAssertEqual(CoachDisplayName.forSaving("דנה"), "דנה")
        XCTAssertNil(CoachDisplayName.forSaving("   "))
        XCTAssertNil(CoachDisplayName.forSaving("Your Coach"))
        XCTAssertNil(CoachDisplayName.forSaving("coach"))
        XCTAssertNotNil(CoachDisplayName.forSaving(String(repeating: "a", count: 40)))
        XCTAssertNil(CoachDisplayName.forSaving(String(repeating: "a", count: 41)))
    }

    func testCoachNameCapCountsCodePoints() {
        let flags = String(repeating: "🇮🇱", count: 25) // 2 code points each
        let capped = CoachDisplayName.capped(flags)
        XCTAssertEqual(capped, String(repeating: "🇮🇱", count: 20))
        XCTAssertTrue(BidiText.fits(capped, limit: CoachDisplayName.maxLength))
    }
}
