import XCTest
import CoreLocation
@testable import IOS_RunSmart_app

@MainActor
final class RecordRunQuickFixTests: XCTestCase {

    // MARK: - Post-run map camera
    // The live map follows the latest fix in LiveRunMapPage; see LiveRunPresentationTests.

    func testPostRunCameraKeyStillBucketsByPointCount() {
        let coords = (0..<100).map { CLLocationCoordinate2D(latitude: 32 + Double($0) * 0.0001, longitude: 34.8) }
        let sameBucket = Array(coords.prefix(95))

        XCTAssertEqual(
            RouteMapView.cameraKey(for: coords),
            RouteMapView.cameraKey(for: coords.dropLast(1).map { $0 } + [CLLocationCoordinate2D(latitude: 1, longitude: 1)])
        )
        XCTAssertEqual(RouteMapView.cameraKey(for: sameBucket), 4)
        XCTAssertEqual(RouteMapView.cameraKey(for: coords), 5)
    }

    // MARK: - Elevation gain

    func testElevationGainIsNilWithoutAltitude() {
        XCTAssertNil(RunRecorder.elevationGainMeters(from: []))
        XCTAssertNil(RunRecorder.elevationGainMeters(from: [point(0, altitude: nil), point(1, altitude: nil)]))
        XCTAssertNil(RunRecorder.elevationGainMeters(from: [point(0, altitude: 10), point(1, altitude: nil)]))
    }

    func testElevationGainIgnoresFlatNoise() throws {
        let noise: [Double] = [100, 102, 99, 101, 98, 102, 100, 101, 99, 102, 98, 100]
        let points = noise.enumerated().map { point($0.offset, altitude: $0.element) }

        let gain = try XCTUnwrap(RunRecorder.elevationGainMeters(from: points))
        XCTAssertEqual(gain, 0, accuracy: 0.001)
    }

    func testElevationGainCountsRealClimb() throws {
        // 0 to 50 m in 5 m steps, with a little noise on top.
        let points = stride(from: 0, through: 50, by: 5).enumerated().map { index, altitude in
            point(index, altitude: 100 + Double(altitude) + (index.isMultiple(of: 2) ? 1 : -1))
        }

        let gain = try XCTUnwrap(RunRecorder.elevationGainMeters(from: points))
        XCTAssertEqual(gain, 50, accuracy: 4)
    }

    func testElevationGainDoesNotCountDescent() throws {
        let points = [100.0, 90, 80, 70].enumerated().map { point($0.offset, altitude: $0.element) }

        let gain = try XCTUnwrap(RunRecorder.elevationGainMeters(from: points))
        XCTAssertEqual(gain, 0, accuracy: 0.001)
    }

    // MARK: - Debrief workout type

    func testDebriefWorkoutTypePlannedTypeWins() {
        // A pace/HR profile that would classify as "hard" on its own.
        let run = makeRun(pace: 270, heartRate: 175)

        XCTAssertEqual(SupabaseRunSmartServices.debriefWorkoutType(planned: .long, for: run), "long")
        XCTAssertEqual(SupabaseRunSmartServices.debriefWorkoutType(planned: .tempo, for: run), "tempo")
        XCTAssertEqual(SupabaseRunSmartServices.debriefWorkoutType(planned: .easy, for: run), "easy")
        XCTAssertEqual(SupabaseRunSmartServices.debriefWorkoutType(planned: .intervals, for: run), "intervals")
    }

    func testDebriefWorkoutTypeFallsBackToHeartRateThenPace() {
        XCTAssertEqual(SupabaseRunSmartServices.debriefWorkoutType(planned: nil, for: makeRun(pace: 360, heartRate: 170)), "hard")
        XCTAssertEqual(SupabaseRunSmartServices.debriefWorkoutType(planned: nil, for: makeRun(pace: 360, heartRate: 150)), "moderate")
        XCTAssertEqual(SupabaseRunSmartServices.debriefWorkoutType(planned: nil, for: makeRun(pace: 360, heartRate: 130)), "easy")
        XCTAssertEqual(SupabaseRunSmartServices.debriefWorkoutType(planned: nil, for: makeRun(pace: 450, heartRate: nil)), "easy")
        XCTAssertEqual(SupabaseRunSmartServices.debriefWorkoutType(planned: nil, for: makeRun(pace: 360, heartRate: nil)), "steady")
        XCTAssertEqual(SupabaseRunSmartServices.debriefWorkoutType(planned: nil, for: makeRun(pace: 290, heartRate: nil)), "moderate")
    }

    // MARK: - Helpers

    private func point(_ index: Int, altitude: Double?) -> RunRoutePoint {
        RunRoutePoint(
            latitude: 32 + Double(index) * 0.0001,
            longitude: 34.8,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 5),
            horizontalAccuracy: 5,
            altitude: altitude
        )
    }

    private func makeRun(pace: Double, heartRate: Int?) -> RecordedRun {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800),
            distanceMeters: 5_000,
            movingTimeSeconds: 1_800,
            averagePaceSecondsPerKm: pace,
            averageHeartRateBPM: heartRate,
            routePoints: [],
            routeMatchResult: nil,
            syncedAt: nil
        )
    }
}
