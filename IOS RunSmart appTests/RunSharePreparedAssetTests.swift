import Foundation
import XCTest
@testable import IOS_RunSmart_app

/// A ready file belongs to its immutable render input. UI changes must invalidate it before
/// asynchronous regeneration starts, especially when the runner turns location sharing off.
@MainActor
final class RunSharePreparedAssetTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/RunSmart-test-export.png")
    private let time = Date(timeIntervalSince1970: 1_792_713_600)

    private func makeRun() -> RecordedRun {
        RecordedRun(
            id: UUID(), providerActivityID: nil, source: .runSmart,
            startedAt: time, endedAt: time.addingTimeInterval(2_439),
            distanceMeters: 6_800, movingTimeSeconds: 2_439, averagePaceSecondsPerKm: 2_439 / 6.8,
            averageHeartRateBPM: nil,
            routePoints: [
                RunRoutePoint(latitude: 32.06, longitude: 34.76, timestamp: time,
                              horizontalAccuracy: 5, altitude: nil),
                RunRoutePoint(latitude: 32.07, longitude: 34.76, timestamp: time.addingTimeInterval(400),
                              horizontalAccuracy: 5, altitude: nil)
            ],
            syncedAt: nil, title: "Selected run"
        )
    }

    private func key(
        run: RecordedRun?, format: RunShareAssetFormat = .story,
        includeMap: Bool = true, insight: String? = "An easy coastal run."
    ) -> RunShareRenderKey {
        RunShareRenderKey(format: format, run: run, includeMap: includeMap, insight: insight)
    }

    private func asset(for key: RunShareRenderKey) -> RunSharePreparedAsset {
        // A captured render may use a presentation-local title/locale. The handoff must use this
        // exact snapshot, rather than reconstructing its caption from key.run at share time.
        let captured = RunShareSnapshot(
            title: "Captured export title", dateLabel: "23 Oct 2026",
            distanceLabel: "6.8", distanceUnit: "km", durationLabel: "40:39", paceLabel: "5:59 /km",
            sourceLabel: "RunSmart", insight: key.insight ?? "",
            privacyNote: key.includeMap ? RouteSharePrivacy.privacyNote : "No location data is included.",
            distanceMeters: 6_800, movingTimeSeconds: 2_439, routePoints: []
        )
        return RunSharePreparedAsset(key: key, snapshot: captured, fileURL: url)
    }

    private func assertUnavailable(
        _ asset: RunSharePreparedAsset, matching current: RunShareRenderKey,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertNil(asset.url(matching: current), file: file, line: line)
        XCTAssertNil(asset.activityItem(matching: current), file: file, line: line)
    }

    func testUnchangedRenderKeySharesTheCapturedFileAndCaption() throws {
        let selected = makeRun()
        let unchanged = key(run: selected)
        let ready = asset(for: unchanged)
        let item = try XCTUnwrap(ready.activityItem(matching: unchanged))
        XCTAssertEqual(ready.url(matching: unchanged), url)
        XCTAssertEqual(item.fileURL, url)
        XCTAssertEqual(item.caption, ready.snapshot.shareCaption)
        XCTAssertTrue(item.caption.contains("Captured export title"))
        XCTAssertFalse(item.caption.contains("Selected run"))
    }

    func testMapOptOutImmediatelyInvalidatesTheReadyMapAsset() {
        let selected = makeRun()
        let ready = asset(for: key(run: selected, includeMap: true))
        assertUnavailable(ready, matching: key(run: selected, includeMap: false))
    }

    func testNewRunWithIdenticalMetricsCannotReuseThePreviousFile() {
        let selected = makeRun()
        var replacement = selected
        replacement.id = UUID()
        let ready = asset(for: key(run: selected))
        assertUnavailable(ready, matching: key(run: replacement))
    }

    func testRefreshedInsightContentInvalidatesTheReadyFile() {
        let selected = makeRun()
        let ready = asset(for: key(run: selected, insight: "An easy coastal run."))
        assertUnavailable(ready, matching: key(run: selected, insight: "A controlled finish to today's session."))
    }

    func testInsightOptOutImmediatelyInvalidatesTheReadyFile() {
        let selected = makeRun()
        let ready = asset(for: key(run: selected, insight: "An easy coastal run."))
        assertUnavailable(ready, matching: key(run: selected, insight: nil))
    }

    func testFormatChangeCannotHandAnOldPNGToTheVideoShareAction() {
        let selected = makeRun()
        let ready = asset(for: key(run: selected, format: .story))
        assertUnavailable(ready, matching: key(run: selected, format: .video))
        assertUnavailable(ready, matching: key(run: selected, format: .feed))
    }

    func testSameRunIDWithUpdatedMetricsStillInvalidatesItsExport() {
        let selected = makeRun()
        var updated = selected
        updated.distanceMeters = 7_000
        updated.movingTimeSeconds = 2_500
        let originalKey = key(run: selected)
        let updatedKey = key(run: updated)
        let ready = asset(for: originalKey)
        XCTAssertNotEqual(originalKey, updatedKey)
        XCTAssertEqual(Set([originalKey, updatedKey]).count, 2)
        assertUnavailable(ready, matching: updatedKey)
    }

    func testRouteRefreshWithTheSamePointCountCannotReuseOldMapArtwork() {
        let selected = makeRun()
        var updated = selected
        updated.routePoints[1].longitude += 0.001
        XCTAssertEqual(selected.routePoints.count, updated.routePoints.count)
        let ready = asset(for: key(run: selected))
        assertUnavailable(ready, matching: key(run: updated))
    }

    func testLosingTheSelectedRunInvalidatesItsReadyAsset() {
        let ready = asset(for: key(run: makeRun()))
        assertUnavailable(ready, matching: key(run: nil))
    }
}
