import XCTest
@testable import IOS_RunSmart_app

/// Share images and video print only AI-written coach text, never the server's fallback copy.
final class RunShareInsightTests: XCTestCase {
    private let run = RecordedRun(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, providerActivityID: nil, source: .runSmart,
        startedAt: Date(timeIntervalSince1970: 1_793_001_600), endedAt: Date(timeIntervalSince1970: 1_793_003_900),
        distanceMeters: 6_600, movingTimeSeconds: 2_178, averagePaceSecondsPerKm: 330, averageHeartRateBPM: nil,
        routePoints: [], syncedAt: nil
    )

    private func payload(_ summary: String) throws -> RunSmartDTO.RunReportPayload {
        try JSONDecoder().decode(RunSmartDTO.RunReportPayload.self, from: Data("{\"summary\": \(summary)}".utf8))
    }

    func testSummaryLinesExposeTheWhatWentWellLine() throws {
        let lines = try payload("""
        ["6.60 km in 36:18 at 5:30/km.", "  Even pace from the first kilometre to the last.  ", "Aerobic base.", "Next: easy 5 km."]
        """)
        XCTAssertEqual(lines.shareHighlight, "Even pace from the first kilometre to the last.")
        XCTAssertNil(try payload("\"A single summary string.\"").shareHighlight)
        XCTAssertNil(try payload("[\"Only a headline.\"]").shareHighlight)
    }

    func testOnlyAnAIReportCarriesTheShareLine() throws {
        let lines = try payload("[\"Run logged.\", \"Short run still counts for habit building.\"]")
        XCTAssertNil(SupabaseRunSmartServices.report(from: lines, run: run, source: "fallback").shareHighlight)
        XCTAssertNil(SupabaseRunSmartServices.report(from: lines, run: run).shareHighlight)
        XCTAssertEqual(SupabaseRunSmartServices.report(from: lines, run: run, source: "ai").shareHighlight,
                       "Short run still counts for habit building.")
    }

    func testRunReportShareUsesTheShareLineAndNeverTheFullSummary() throws {
        let lines = try payload("[\"Run logged.\", \"Short run still counts for habit building.\"]")
        let fallback = ProgressSharePayload.runReport(SupabaseRunSmartServices.report(from: lines, run: run, source: "fallback"))
        XCTAssertEqual(fallback.mediaInsight, "")
        XCTAssertEqual(fallback.insight, "Run logged. Short run still counts for habit building.")
        let ai = ProgressSharePayload.runReport(SupabaseRunSmartServices.report(from: lines, run: run, source: "ai"))
        XCTAssertEqual(ai.mediaInsight, "Short run still counts for habit building.")
    }

    func testReportsCachedBeforeTheShareLineExistedDecodeWithoutOne() throws {
        let cached = SupabaseRunSmartServices.report(from: try payload("\"Saved earlier.\""), run: run, source: "ai")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(cached)) as? [String: Any])
        json.removeValue(forKey: "shareHighlight")
        let decoded = try JSONDecoder().decode(RunReportDetail.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.shareHighlight)
    }
}
