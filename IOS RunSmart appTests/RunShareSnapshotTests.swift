import XCTest
import CoreLocation
@testable import IOS_RunSmart_app

/// Export data must come from one real activity snapshot; map opt-in never exposes raw ends.
@MainActor
final class RunShareSnapshotTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_792_713_600)
    private let locale = Locale(identifier: "en_US_POSIX")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func point(metersNorth: Double, index: Int, longitude: Double = 34.78) -> RunRoutePoint {
        RunRoutePoint(
            latitude: 32 + metersNorth / 110_850,
            longitude: longitude,
            timestamp: startedAt.addingTimeInterval(Double(index) * 35),
            horizontalAccuracy: 5,
            altitude: nil
        )
    }

    private func straightRoute(meters: Int = 2_000) -> [RunRoutePoint] {
        stride(from: 0, through: meters, by: 100).enumerated().map {
            point(metersNorth: Double($0.element), index: $0.offset)
        }
    }

    private func makeRun(
        points: [RunRoutePoint] = [],
        distance: Double = 6_800,
        seconds: Double = 2_439,
        storedPace: Double = 367
    ) -> RecordedRun {
        RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(2_700),
            distanceMeters: distance,
            movingTimeSeconds: seconds,
            averagePaceSecondsPerKm: storedPace,
            averageHeartRateBPM: nil,
            routePoints: points,
            syncedAt: nil,
            title: "October coastal run"
        )
    }

    private func snapshot(_ run: RecordedRun, includeMap: Bool = false) -> RunShareSnapshot {
        RunShareSnapshot.make(run: run, includeMap: includeMap, locale: locale, calendar: calendar)
    }

    private func meters(_ first: RunRoutePoint, _ second: RunRoutePoint) -> Double {
        CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
    }

    func testMapOffDoesNotExposeAnyRecordedCoordinates() {
        let exported = snapshot(makeRun(points: straightRoute()))
        XCTAssertTrue(exported.routePoints.isEmpty)
        XCTAssertFalse(exported.privacyNote.contains("Route shown"))
    }

    func testOptedInMapDropsBothHiddenEnds() throws {
        let points = straightRoute()
        let exported = snapshot(makeRun(points: points), includeMap: true)
        XCTAssertFalse(exported.routePoints.isEmpty)
        for kept in exported.routePoints {
            XCTAssertGreaterThanOrEqual(meters(points[0], kept), 199)
            XCTAssertGreaterThanOrEqual(meters(kept, points[points.count - 1]), 199)
        }
        XCTAssertEqual(exported.privacyNote, RouteSharePrivacy.privacyNote)
        XCTAssertNotEqual(try XCTUnwrap(exported.routePoints.first).id, points.first?.id)
        XCTAssertNotEqual(try XCTUnwrap(exported.routePoints.last).id, points.last?.id)
    }

    func testOutAndBackRetainsTurnaroundAndReturnOrder() throws {
        let outwardDistances = Array(stride(from: 0, through: 3_400, by: 100))
        let returnDistances = Array(stride(from: 3_300, through: 0, by: -100))
        let points = (outwardDistances + returnDistances).enumerated().map {
            point(metersNorth: Double($0.element), index: $0.offset)
        }
        let exported = snapshot(makeRun(points: points), includeMap: true)
        let turnaroundID = points[outwardDistances.count - 1].id
        let turnIndex = try XCTUnwrap(exported.routePoints.firstIndex { $0.id == turnaroundID })
        XCTAssertGreaterThan(turnIndex, 0)
        XCTAssertLessThan(turnIndex, exported.routePoints.count - 1)
        XCTAssertLessThan(exported.routePoints[turnIndex - 1].latitude, exported.routePoints[turnIndex].latitude)
        XCTAssertLessThan(exported.routePoints[turnIndex + 1].latitude, exported.routePoints[turnIndex].latitude)
        let originalIndices = try exported.routePoints.map { kept in
            try XCTUnwrap(points.firstIndex { $0.id == kept.id })
        }
        XCTAssertTrue(zip(originalIndices, originalIndices.dropFirst()).allSatisfy { $0 < $1 })
        XCTAssertEqual(exported.distanceMeters, 6_800)
        XCTAssertEqual(exported.distanceLabel, "6.8")
        for kept in exported.routePoints {
            XCTAssertGreaterThanOrEqual(meters(points[0], kept), 199)
        }
    }

    func testPauseGapRemainsASegmentBreakInsteadOfAConnectingLine() throws {
        var points = straightRoute(meters: 1_200)
        var second = straightRoute(meters: 1_200).enumerated().map { index, old -> RunRoutePoint in
            var point = old
            point.longitude += 0.03
            point.timestamp = startedAt.addingTimeInterval(Double(index + points.count) * 35)
            return point
        }
        second[0].startsNewSegment = true
        let resumedID = second[0].id
        points.append(contentsOf: second)
        let exported = snapshot(makeRun(points: points), includeMap: true)
        XCTAssertEqual(try XCTUnwrap(exported.routePoints.first { $0.id == resumedID }).startsNewSegment, true)
        XCTAssertEqual(RoutePointSegments.drawableSegments(exported.routePoints).count, 2)
        XCTAssertLessThan(RouteSharePrivacy.pathLengthMeters(exported.routePoints), 2_100)
    }

    func testInvalidCoordinatesAreRemovedAndDoNotJoinAcrossTheGap() throws {
        var points = straightRoute()
        let afterGapID = points[10].id
        var invalid = points[9]
        invalid.id = UUID()
        invalid.latitude = .nan
        points.insert(invalid, at: 10)
        invalid.id = UUID()
        invalid.latitude = 95
        invalid.longitude = 200
        points.insert(invalid, at: 11)
        let exported = snapshot(makeRun(points: points), includeMap: true)
        XCTAssertFalse(exported.routePoints.isEmpty)
        XCTAssertTrue(exported.routePoints.allSatisfy {
            CLLocationCoordinate2DIsValid($0.coordinate) && $0.latitude.isFinite && $0.longitude.isFinite
        })
        XCTAssertEqual(try XCTUnwrap(exported.routePoints.first { $0.id == afterGapID }).startsNewSegment, true)
        XCTAssertEqual(RoutePointSegments.drawableSegments(exported.routePoints).count, 2)
    }

    func testShortRouteCannotLeakItsStartThroughATinyMapRemainder() {
        let exported = snapshot(makeRun(points: straightRoute(meters: 300)), includeMap: true)
        XCTAssertTrue(exported.routePoints.isEmpty)
        XCTAssertFalse(exported.privacyNote.contains("Route shown"))
    }

    func testMissingGPSNeverSubstitutesADemoRoute() {
        let exported = snapshot(makeRun(), includeMap: true)
        XCTAssertTrue(exported.routePoints.isEmpty)
        XCTAssertEqual(exported.distanceLabel, "6.8")
        XCTAssertEqual(exported.durationLabel, "40:39")
        XCTAssertFalse(exported.privacyNote.contains("Route shown"))
    }

    func testMetricsUseTheSameDistanceAndMovingTimeRatherThanStoredPace() {
        let exported = snapshot(makeRun(storedPace: 367))
        XCTAssertEqual(exported.distanceLabel, "6.8")
        XCTAssertEqual(exported.distanceUnit, "km")
        XCTAssertEqual(exported.durationLabel, "40:39")
        XCTAssertEqual(exported.paceLabel, "5:59 /km")
        XCTAssertEqual(exported.movingTimeSeconds, 2_439)
    }

    func testZeroMetricsRenderMissingValuesInsteadOfInventedStats() {
        let exported = snapshot(makeRun(distance: 0, seconds: 0, storedPace: 100))
        XCTAssertEqual(exported.distanceLabel, "--")
        XCTAssertEqual(exported.durationLabel, "--")
        XCTAssertEqual(exported.paceLabel, "--")
    }

    func testNegativeDistanceCannotProduceAValidPace() {
        let exported = snapshot(makeRun(distance: -100, seconds: 2_439))
        XCTAssertEqual(exported.distanceLabel, "--")
        XCTAssertEqual(exported.paceLabel, "--")
        XCTAssertEqual(exported.durationLabel, "40:39")
    }

    func testNonfiniteMetricInputsDoNotEscapeIntoLabelsOrRendererNumbers() {
        let exported = snapshot(makeRun(distance: .infinity, seconds: .nan, storedPace: .infinity))
        XCTAssertEqual(exported.distanceLabel, "--")
        XCTAssertEqual(exported.durationLabel, "--")
        XCTAssertEqual(exported.paceLabel, "--")
        XCTAssertTrue(exported.distanceMeters.isFinite)
        XCTAssertTrue(exported.movingTimeSeconds.isFinite)
    }

    func testMissingMovingTimeDoesNotInventPaceFromTheStoredAverage() {
        let exported = snapshot(makeRun(seconds: 0, storedPace: 367))
        XCTAssertEqual(exported.distanceLabel, "6.8")
        XCTAssertEqual(exported.durationLabel, "--")
        XCTAssertEqual(exported.paceLabel, "--")
    }

    func testSnapshotPreservesRunnerTitleAndGarminAttribution() {
        var run = makeRun()
        run.source = .garmin
        run.sourceDeviceName = "Forerunner 265"
        let exported = snapshot(run)
        XCTAssertEqual(exported.title, "October coastal run")
        XCTAssertTrue(exported.sourceLabel.contains("Garmin"))
        XCTAssertTrue(exported.sourceLabel.contains("Forerunner 265"))
    }

    func testExportFormatsUseSocialAssetPixelDimensions() {
        XCTAssertEqual(RunShareAssetFormat.story.pixelSize, CGSize(width: 1_080, height: 1_920))
        XCTAssertEqual(RunShareAssetFormat.feed.pixelSize, CGSize(width: 1_080, height: 1_350))
        XCTAssertEqual(RunShareAssetFormat.video.pixelSize, CGSize(width: 1_080, height: 1_920))
    }

    func testDiscoveryLinkPointsDirectlyToTheVerifiedIOSListing() {
        XCTAssertEqual(ExternalURLs.appStore.scheme, "https")
        XCTAssertEqual(ExternalURLs.appStore.host, "apps.apple.com")
        XCTAssertTrue(ExternalURLs.appStore.path.contains("id6768297840"))
        XCTAssertFalse(ExternalURLs.appStore.absoluteString.contains("runsmart-ai.com"))
    }
}
