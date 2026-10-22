import XCTest
import CoreLocation
import HealthKit
@testable import IOS_RunSmart_app

/// Record-a-run S11: what RunSmart writes to Apple Health. HealthKit cannot write in unit
/// tests, so these cover the pure plan the service turns into HealthKit objects.
final class HealthKitWorkoutPlanTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func point(_ seconds: TimeInterval, lat: Double, newSegment: Bool? = nil) -> RunRoutePoint {
        RunRoutePoint(
            latitude: lat,
            longitude: 34.78,
            timestamp: at(seconds),
            horizontalAccuracy: 5,
            altitude: 10,
            startsNewSegment: newSegment
        )
    }

    private func makeRun(
        durationSeconds: TimeInterval = 1_800,
        distance: Double = 5_000,
        pauses: [RunPauseInterval]? = nil,
        route: [RunRoutePoint] = [],
        kilocalories: Double? = nil,
        source: RunSmartDataSource = .runSmart
    ) -> RecordedRun {
        RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: source,
            startedAt: start,
            endedAt: at(durationSeconds),
            distanceMeters: distance,
            movingTimeSeconds: durationSeconds,
            averagePaceSecondsPerKm: 360,
            averageHeartRateBPM: nil,
            routePoints: route,
            syncedAt: nil,
            pauseIntervals: pauses,
            estimatedActiveKilocalories: kilocalories
        )
    }

    // MARK: Pause events

    func testPauseAndResumeEventsComeFromIntervals() {
        let run = makeRun(pauses: [
            RunPauseInterval(start: at(300), end: at(360)),
            RunPauseInterval(start: at(900), end: at(930))
        ])
        let plan = HealthKitWorkoutPlan.make(for: run)
        XCTAssertEqual(plan.pauseEvents, [
            .init(kind: .pause, date: at(300)),
            .init(kind: .resume, date: at(360)),
            .init(kind: .pause, date: at(900)),
            .init(kind: .resume, date: at(930))
        ])
    }

    func testPauseOpenAtEndHasNoResume() {
        let run = makeRun(durationSeconds: 1_000, pauses: [RunPauseInterval(start: at(700), end: at(1_000))])
        let plan = HealthKitWorkoutPlan.make(for: run)
        XCTAssertEqual(plan.pauseEvents, [.init(kind: .pause, date: at(700))])
    }

    func testPauseRunningPastTheEndIsCutAtTheEnd() {
        let run = makeRun(durationSeconds: 1_000, pauses: [RunPauseInterval(start: at(700), end: at(5_000))])
        let plan = HealthKitWorkoutPlan.make(for: run)
        XCTAssertEqual(plan.pauseEvents, [.init(kind: .pause, date: at(700))])
        XCTAssertEqual(plan.distanceSamples.map(\.end), [at(700)])
    }

    func testEmptyOverlappingAndOutOfRangePausesAreCleaned() {
        let pauses = [
            RunPauseInterval(start: at(100), end: at(100)),
            RunPauseInterval(start: at(200), end: at(400)),
            RunPauseInterval(start: at(300), end: at(500)),
            RunPauseInterval(start: at(-50), end: at(-10)),
            RunPauseInterval(start: at(900), end: at(800))
        ]
        let plan = HealthKitWorkoutPlan.make(for: makeRun(pauses: pauses))
        XCTAssertEqual(plan.pauseEvents, [
            .init(kind: .pause, date: at(200)),
            .init(kind: .resume, date: at(500))
        ])
    }

    func testNoPausesMeansNoEvents() {
        XCTAssertTrue(HealthKitWorkoutPlan.make(for: makeRun(pauses: nil)).pauseEvents.isEmpty)
        XCTAssertTrue(HealthKitWorkoutPlan.make(for: makeRun(pauses: [])).pauseEvents.isEmpty)
    }

    // MARK: Distance

    func testDistanceSamplesAddUpToRunDistanceAndSkipPauses() {
        // Two pauses, so three moving stretches: 0-300, 360-900, 930-1800.
        let route = [
            point(0, lat: 32.0000), point(150, lat: 32.0010), point(300, lat: 32.0020),
            point(360, lat: 32.0030, newSegment: true), point(900, lat: 32.0060),
            point(930, lat: 32.0070, newSegment: true), point(1_800, lat: 32.0100)
        ]
        let run = makeRun(
            distance: 5_000,
            pauses: [
                RunPauseInterval(start: at(300), end: at(360)),
                RunPauseInterval(start: at(900), end: at(930))
            ],
            route: route
        )
        let samples = HealthKitWorkoutPlan.make(for: run).distanceSamples

        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.reduce(0) { $0 + $1.meters }, 5_000, accuracy: 0.0001)
        XCTAssertEqual(samples.map(\.start), [at(0), at(360), at(930)])
        XCTAssertEqual(samples.map(\.end), [at(300), at(900), at(1_800)])
        // The 0-300 s stretch covers 0.002 degrees, the last one 0.003: more route, more meters.
        XCTAssertGreaterThan(samples[2].meters, samples[0].meters)
    }

    func testDistanceFallsBackToMovingTimeWithoutARoute() {
        let run = makeRun(durationSeconds: 1_000, distance: 3_000, pauses: [RunPauseInterval(start: at(250), end: at(500))])
        let samples = HealthKitWorkoutPlan.make(for: run).distanceSamples
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples.reduce(0) { $0 + $1.meters }, 3_000, accuracy: 0.0001)
        // 250 s then 500 s of moving time.
        XCTAssertEqual(samples[0].meters, 1_000, accuracy: 0.001)
        XCTAssertEqual(samples[1].meters, 2_000, accuracy: 0.001)
    }

    func testNoDistanceSamplesForZeroDistance() {
        XCTAssertTrue(HealthKitWorkoutPlan.make(for: makeRun(distance: 0)).distanceSamples.isEmpty)
        XCTAssertTrue(HealthKitWorkoutPlan.make(for: makeRun(distance: .nan)).distanceSamples.isEmpty)
    }

    func testSingleStretchRunWritesOneSampleWithFullDistance() {
        let samples = HealthKitWorkoutPlan.make(for: makeRun(distance: 4_200)).distanceSamples
        XCTAssertEqual(samples, [.init(start: at(0), end: at(1_800), meters: 4_200)])
    }

    // MARK: Route

    func testRouteSplitsAtSegmentStartsAndDropsSinglePointSegments() {
        let route = [
            point(0, lat: 32.000), point(10, lat: 32.001),
            point(20, lat: 32.002, newSegment: true), point(30, lat: 32.003),
            point(40, lat: 32.004, newSegment: true)
        ]
        let segments = HealthKitWorkoutPlan.routeSegments(from: route)
        XCTAssertEqual(segments.map(\.count), [2, 2])
    }

    func testRouteIsSkippedBelowTwoPoints() {
        XCTAssertTrue(HealthKitWorkoutPlan.make(for: makeRun(route: [])).routeSegments.isEmpty)
        XCTAssertTrue(HealthKitWorkoutPlan.make(for: makeRun(route: [point(0, lat: 32.0)])).routeSegments.isEmpty)
        let brokenUp = [point(0, lat: 32.0), point(10, lat: 32.1, newSegment: true)]
        XCTAssertTrue(HealthKitWorkoutPlan.routeSegments(from: brokenUp).isEmpty)
    }

    func testRouteDropsPointsWithoutAValidFix() {
        var bad = point(5, lat: 32.0005)
        bad.horizontalAccuracy = -1
        let route = [point(0, lat: 32.0), bad, point(10, lat: 32.001)]
        XCTAssertEqual(HealthKitWorkoutPlan.routeSegments(from: route).map(\.count), [2])
    }

    func testLocationKeepsCoordinateTimeAndAltitude() {
        let location = HealthKitWorkoutPlan.location(for: point(42, lat: 32.5))
        XCTAssertEqual(location.coordinate.latitude, 32.5, accuracy: 1e-9)
        XCTAssertEqual(location.timestamp, at(42))
        XCTAssertEqual(location.altitude, 10, accuracy: 1e-9)
        XCTAssertGreaterThan(location.verticalAccuracy, 0)

        var noAltitude = point(42, lat: 32.5)
        noAltitude.altitude = nil
        XCTAssertLessThan(HealthKitWorkoutPlan.location(for: noAltitude).verticalAccuracy, 0)
    }

    // MARK: Energy and metadata

    func testEnergySampleOnlyWhenThereIsAnEstimate() {
        XCTAssertNil(HealthKitWorkoutPlan.make(for: makeRun(kilocalories: nil)).energy)
        XCTAssertNil(HealthKitWorkoutPlan.make(for: makeRun(kilocalories: 0)).energy)
        XCTAssertNil(HealthKitWorkoutPlan.make(for: makeRun(kilocalories: .nan)).energy)
        XCTAssertNil(HealthKitWorkoutPlan.make(for: makeRun(kilocalories: -5)).energy)

        let energy = HealthKitWorkoutPlan.make(for: makeRun(kilocalories: 350)).energy
        XCTAssertEqual(energy, .init(start: at(0), end: at(1_800), kilocalories: 350))
    }

    func testMetadataKeepsRunSmartRunIDAndMarksOutdoor() {
        let run = makeRun()
        let metadata = HealthKitWorkoutPlan.metadata(for: run)
        XCTAssertEqual(metadata[HealthKitWorkoutPlan.runIDMetadataKey] as? String, run.id.uuidString)
        XCTAssertEqual(metadata["RunSmartRunID"] as? String, run.id.uuidString)
        XCTAssertEqual(metadata["RunSmartSource"] as? String, "RunSmart")
        XCTAssertEqual(metadata[HKMetadataKeyIndoorWorkout] as? Bool, false)
    }

    func testImportSkipsOwnWorkoutOnlyWhenTheRunIsStoredLocally() {
        let run = makeRun()
        let metadata = HealthKitWorkoutPlan.metadata(for: run)
        XCTAssertTrue(HealthKitWorkoutPlan.isStoredLocally(metadata: metadata, localRunIDs: [run.id]))
        // Local store empty (reinstall) or a different run: import it as before.
        XCTAssertFalse(HealthKitWorkoutPlan.isStoredLocally(metadata: metadata, localRunIDs: []))
        XCTAssertFalse(HealthKitWorkoutPlan.isStoredLocally(metadata: metadata, localRunIDs: [UUID()]))
        // Workouts from other apps carry no RunSmart id.
        XCTAssertFalse(HealthKitWorkoutPlan.isStoredLocally(metadata: nil, localRunIDs: [run.id]))
        XCTAssertFalse(HealthKitWorkoutPlan.isStoredLocally(metadata: ["RunSmartRunID": "not-a-uuid"], localRunIDs: [run.id]))
    }

    func testEndBeforeStartCollapsesToAnEmptyPlan() {
        var run = makeRun()
        run.endedAt = at(-60)
        let plan = HealthKitWorkoutPlan.make(for: run)
        XCTAssertEqual(plan.end, plan.start)
        XCTAssertTrue(plan.distanceSamples.isEmpty)
        XCTAssertNil(plan.energy)
    }
}
