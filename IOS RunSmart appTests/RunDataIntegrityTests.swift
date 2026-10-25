import XCTest
import CoreLocation
@testable import IOS_RunSmart_app

/// Run data integrity (record-run plan S2): splits that ignore pauses, no 8-split cap,
/// a GPS jitter filter, and a current pace that decays when the runner stops.
@MainActor
final class RunDataIntegrityTests: XCTestCase {
    private static let baseLatitude = 32.08
    private static let baseLongitude = 34.78
    /// Real length of one degree of latitude here, so test distances match CLLocation's math.
    private static let metersPerDegreeLatitude = CLLocation(latitude: baseLatitude, longitude: baseLongitude)
        .distance(from: CLLocation(latitude: baseLatitude + 1, longitude: baseLongitude))

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-integrity-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        RunCheckpointStore.flush()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Helpers

    private func makeRecorder() -> RunRecorder {
        let recorder = RunRecorder(store: .shared, checkpointStore: RunCheckpointStore(directoryURL: directory))
        recorder.authorizationStatusProvider = { .authorizedWhenInUse }
        return recorder
    }

    private func latitude(metersNorth: Double) -> Double {
        Self.baseLatitude + metersNorth / Self.metersPerDegreeLatitude
    }

    private func longitude(metersEast: Double) -> Double {
        Self.baseLongitude + metersEast / (Self.metersPerDegreeLatitude * cos(Self.baseLatitude * .pi / 180))
    }

    private func location(
        metersNorth: Double,
        metersEast: Double = 0,
        at timestamp: Date,
        accuracy: Double = 8,
        speed: Double = 3.3
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude(metersNorth: metersNorth), longitude: longitude(metersEast: metersEast)),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            course: -1,
            speed: speed,
            timestamp: timestamp
        )
    }

    private func routePoint(metersNorth: Double, at timestamp: Date, newSegment: Bool = false) -> RunRoutePoint {
        RunRoutePoint(
            latitude: latitude(metersNorth: metersNorth),
            longitude: Self.baseLongitude,
            timestamp: timestamp,
            horizontalAccuracy: 8,
            altitude: nil,
            startsNewSegment: newSegment ? true : nil
        )
    }

    /// Steady 5:00/km points every 10 m (3 s apart) from `startMeters` for `meters`.
    private func steadyPoints(from startMeters: Double, meters: Double, at start: Date, newSegmentFirst: Bool = false) -> [RunRoutePoint] {
        let steps = Int((meters / 10).rounded())
        return (0...steps).map { step in
            routePoint(
                metersNorth: startMeters + Double(step) * 10,
                at: start.addingTimeInterval(Double(step) * 3),
                newSegment: newSegmentFirst && step == 0
            )
        }
    }

    private func feed(_ recorder: RunRecorder, _ fix: CLLocation) {
        recorder.handleLocationUpdates([fix], now: fix.timestamp)
    }

    /// Deterministic scatter in [-radius, radius] per axis.
    private struct Scatter {
        var state: UInt64 = 0x2545F4914F6CDD1D
        mutating func next(radius: Double) -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double(state >> 11) / Double(1 << 53)
            return (unit * 2 - 1) * radius
        }
    }

    private func standStill(speed: Double) -> Double {
        let recorder = makeRecorder()
        recorder.startAcquiringLocation(startLocationUpdates: false)
        let start = Date()
        var scatter = Scatter()
        feed(recorder, location(
            metersNorth: scatter.next(radius: 12),
            metersEast: scatter.next(radius: 12),
            at: start,
            accuracy: 20,
            speed: speed
        ))
        for second in 1...120 {
            let fix = location(
                metersNorth: scatter.next(radius: 12),
                metersEast: scatter.next(radius: 12),
                at: start.addingTimeInterval(Double(second)),
                accuracy: 20,
                speed: speed
            )
            feed(recorder, fix)
        }
        let distance = recorder.distanceMeters
        recorder.discard()
        return distance
    }

    // MARK: Splits

    func testPauseGapIsNotCountedInSplitsOrDistance() {
        let recorder = makeRecorder()
        recorder.startAcquiringLocation(startLocationUpdates: false)
        let start = Date()

        // 1.5 km at 5:00/km, a 5 minute pause walking 300 m, then 1 km at 5:00/km.
        let firstLeg = steadyPoints(from: 0, meters: 1_500, at: start)
        for point in firstLeg {
            feed(recorder, location(metersNorth: (point.latitude - Self.baseLatitude) * Self.metersPerDegreeLatitude, at: point.timestamp))
        }
        recorder.pause()
        recorder.resume()
        let resumeTime = firstLeg.last!.timestamp.addingTimeInterval(300)
        let secondLeg = steadyPoints(from: 1_800, meters: 1_000, at: resumeTime)
        for point in secondLeg {
            feed(recorder, location(metersNorth: (point.latitude - Self.baseLatitude) * Self.metersPerDegreeLatitude, at: point.timestamp))
        }

        XCTAssertEqual(recorder.distanceMeters, 2_500, accuracy: 25, "distance must exclude the 300 m walked during the pause")
        XCTAssertEqual(recorder.routePoints.filter { $0.startsNewSegment == true }.count, 1)
        XCTAssertEqual(recorder.routePoints[firstLeg.count].startsNewSegment, true, "first fix after resume starts a new segment")

        let splits = RunRecorder.kilometerSplits(from: recorder.routePoints)
        let full = splits.filter { !$0.isPartial }
        XCTAssertEqual(full.count, 2)
        for split in full {
            XCTAssertEqual(split.paceSecondsPerKm, 300, accuracy: 5, "km \(split.km) must not absorb the pause")
        }
        recorder.discard()
    }

    func testFifteenKilometerRunHasFifteenSplitsAndNoPartial() {
        let start = Date(timeIntervalSince1970: 10_000)
        let points = steadyPoints(from: 0, meters: 15_040, at: start)

        let splits = RunRecorder.kilometerSplits(from: points)

        XCTAssertEqual(splits.count, 15)
        XCTAssertFalse(splits.contains { $0.isPartial })
        XCTAssertEqual(splits.map(\.km), Array(1...15))
        for split in splits {
            XCTAssertEqual(split.distanceMeters, 1_000)
            XCTAssertEqual(split.paceSecondsPerKm, 300, accuracy: 2)
        }
    }

    func testRemainderOfAtLeast100MetersAddsPartialSplitWithPacePerKm() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let points = steadyPoints(from: 0, meters: 15_430, at: start)

        let splits = RunRecorder.kilometerSplits(from: points)

        XCTAssertEqual(splits.count, 16)
        let partial = try XCTUnwrap(splits.last)
        XCTAssertTrue(partial.isPartial)
        XCTAssertEqual(partial.km, 16)
        XCTAssertEqual(partial.distanceMeters, 430, accuracy: 10)
        XCTAssertEqual(partial.paceSecondsPerKm, 300, accuracy: 5, "partial pace is normalized per km")
        XCTAssertEqual(splits.filter { !$0.isPartial }.count, 15)
    }

    func testRemainderUnder100MetersAddsNoPartialSplit() {
        let points = steadyPoints(from: 0, meters: 2_060, at: Date(timeIntervalSince1970: 10_000))
        let splits = RunRecorder.kilometerSplits(from: points)
        XCTAssertEqual(splits.count, 2)
        XCTAssertFalse(splits.contains { $0.isPartial })
    }

    func testOptionalSplitCapStillWorksAndSkipsPartial() {
        let points = steadyPoints(from: 0, meters: 5_430, at: Date(timeIntervalSince1970: 10_000))
        let splits = RunRecorder.kilometerSplits(from: points, maxSplits: 3)
        XCTAssertEqual(splits.count, 3)
        XCTAssertFalse(splits.contains { $0.isPartial })
    }

    // MARK: Jitter filter

    func testStandingStillWithZeroSpeedAddsAlmostNoDistance() {
        let distance = standStill(speed: 0)
        XCTAssertLessThan(distance, 30, "standing still with reported speed 0 must not accumulate scatter, got \(distance) m")
    }

    func testStandingStillWithInvalidSpeedAddsFarLessThanBefore() {
        let distance = standStill(speed: -1)
        XCTAssertLessThan(distance, 150, "invalid speed uses the wider accuracy threshold, got \(distance) m (was 735 m)")
    }

    func testOutlierJumpIsRejectedAndRunContinues() {
        let recorder = makeRecorder()
        recorder.startAcquiringLocation(startLocationUpdates: false)
        let start = Date()
        for step in 0...10 {
            feed(recorder, location(metersNorth: Double(step) * 5, at: start.addingTimeInterval(Double(step) * 1.5)))
        }
        let before = recorder.distanceMeters
        let pointsBefore = recorder.routePoints.count

        // 500 m away one second later is 500 m/s.
        feed(recorder, location(metersNorth: 550, at: start.addingTimeInterval(16.5)))
        XCTAssertEqual(recorder.distanceMeters, before, accuracy: 0.001)
        XCTAssertEqual(recorder.routePoints.count, pointsBefore)

        // The next real fix, still near the anchor, is accepted.
        feed(recorder, location(metersNorth: 55, at: start.addingTimeInterval(18)))
        XCTAssertEqual(recorder.distanceMeters, before + 5, accuracy: 0.5)
        recorder.discard()
    }

    func testSteadyRunIsNotUndercountedAtHighAccuracy() {
        let recorder = makeRecorder()
        recorder.startAcquiringLocation(startLocationUpdates: false)
        let start = Date()
        // 5:00/km is 3.33 m/s; one fix every 5 m is every 1.5 s.
        let steps = 400
        for step in 0...steps {
            feed(recorder, location(metersNorth: Double(step) * 5, at: start.addingTimeInterval(Double(step) * 1.5), accuracy: 8))
        }
        let truth = Double(steps) * 5
        XCTAssertEqual(recorder.distanceMeters, truth, accuracy: truth * 0.01)
        recorder.discard()
    }

    func testSlowRealMovementStillAccumulatesAtLowAccuracy() {
        let recorder = makeRecorder()
        recorder.startAcquiringLocation(startLocationUpdates: false)
        let start = Date()
        // 20 m accuracy raises the threshold to 10 m, so 4 m steps are held back by the
        // anchor and counted once they add up.
        for step in 0...100 {
            feed(recorder, location(metersNorth: Double(step) * 4, at: start.addingTimeInterval(Double(step) * 2), accuracy: 20, speed: 2))
        }
        XCTAssertEqual(recorder.distanceMeters, 400, accuracy: 20)
        recorder.discard()
    }

    // MARK: Current pace

    func testCurrentPaceIsAboutFiveMinutesPerKmWhileRunning() throws {
        let start = Date(timeIntervalSince1970: 20_000)
        let points = steadyPoints(from: 0, meters: 400, at: start)
        let last = try XCTUnwrap(points.last)

        let pace = try XCTUnwrap(RunRecorder.currentPace(points: points, now: last.timestamp.addingTimeInterval(2)))

        XCTAssertEqual(pace, 300, accuracy: 6)
    }

    func testCurrentPaceIsNilWhenNewestPointIsOlderThanTenSeconds() throws {
        let start = Date(timeIntervalSince1970: 20_000)
        let points = steadyPoints(from: 0, meters: 400, at: start)
        let last = try XCTUnwrap(points.last)

        XCTAssertNotNil(RunRecorder.currentPace(points: points, now: last.timestamp.addingTimeInterval(9)))
        XCTAssertNil(RunRecorder.currentPace(points: points, now: last.timestamp.addingTimeInterval(15)))
    }

    func testCurrentPaceIsNilForTinyWindowAndEmptyRoute() {
        let start = Date(timeIntervalSince1970: 20_000)
        let points = [routePoint(metersNorth: 0, at: start), routePoint(metersNorth: 5, at: start.addingTimeInterval(3))]
        XCTAssertNil(RunRecorder.currentPace(points: points, now: start.addingTimeInterval(4)))
        XCTAssertNil(RunRecorder.currentPace(points: [], now: start))
    }

    func testCurrentPaceUsesPathDistanceAndStopsAtSegmentStart() throws {
        let start = Date(timeIntervalSince1970: 20_000)
        // 100 m at 5:00/km, a pause, then a new segment: only the new segment may count.
        var points = steadyPoints(from: 0, meters: 100, at: start)
        let resume = points.last!.timestamp.addingTimeInterval(600)
        points += steadyPoints(from: 400, meters: 100, at: resume, newSegmentFirst: true)
        let last = try XCTUnwrap(points.last)

        let pace = try XCTUnwrap(RunRecorder.currentPace(points: points, now: last.timestamp.addingTimeInterval(1)))
        XCTAssertEqual(pace, 300, accuracy: 6, "the 600 s gap and 300 m jump must not leak into current pace")

        // Only a segment start, no distance yet: nothing to measure.
        let freshSegment = Array(points.prefix(while: { $0.startsNewSegment != true })) + [points[11]]
        XCTAssertNil(RunRecorder.currentPace(points: freshSegment, now: points[11].timestamp.addingTimeInterval(1)))
    }

    func testCurrentPaceLabelShowsDashesWithoutMovement() {
        let recorder = makeRecorder()
        XCTAssertEqual(recorder.currentPaceLabel, "--")
    }

    // MARK: Pause intervals

    func testRecorderRecordsPauseIntervalsAndCarriesThemInCheckpoint() throws {
        let recorder = makeRecorder()
        recorder.startAcquiringLocation(startLocationUpdates: false)
        let start = Date()
        feed(recorder, location(metersNorth: 0, at: start))
        feed(recorder, location(metersNorth: 10, at: start.addingTimeInterval(3)))

        recorder.pause()
        recorder.resume()
        RunCheckpointStore.flush()
        let checkpoint = try XCTUnwrap(RunCheckpointStore(directoryURL: directory).load())
        XCTAssertEqual(checkpoint.pauseIntervals?.count, 1)

        recorder.pause()
        let run = try XCTUnwrap(recorder.finish())

        let intervals = try XCTUnwrap(run.pauseIntervals)
        XCTAssertEqual(intervals.count, 2, "a pause still open at finish ends at finish time")
        XCTAssertTrue(intervals.allSatisfy { $0.end >= $0.start })
        XCTAssertEqual(intervals[1].end, run.endedAt)
    }

    func testFirstPointAfterRecoveredResumeStartsNewSegment() throws {
        let store = RunCheckpointStore(directoryURL: directory)
        let now = Date()
        let startedAt = now.addingTimeInterval(-600)
        store.save(RunSessionCheckpoint(
            startedAt: startedAt,
            accumulatedPausedSeconds: 0,
            pausedAt: nil,
            wasPaused: false,
            routePoints: [
                routePoint(metersNorth: 0, at: startedAt),
                routePoint(metersNorth: 100, at: startedAt.addingTimeInterval(30))
            ],
            distanceMeters: 100,
            workoutTitle: nil,
            savedAt: now.addingTimeInterval(-120)
        ))
        let recorder = makeRecorder()
        XCTAssertNotNil(recorder.pendingRecovery)

        recorder.resumeRecoveredRun(startLocationUpdates: false)
        recorder.resume()
        feed(recorder, location(metersNorth: 400, at: now))

        XCTAssertEqual(recorder.routePoints.last?.startsNewSegment, true)
        XCTAssertEqual(recorder.distanceMeters, 100, accuracy: 0.001, "the gap since the checkpoint adds no distance")
        recorder.discard()
    }

    // MARK: Backwards compatibility

    func testOldStoredJSONWithoutNewFieldsStillDecodes() throws {
        let pointJSON = """
        {"id":"6F1B8F8E-3B0B-4D4B-9C57-0C3B6F6F0001","latitude":32.08,"longitude":34.78,"timestamp":1000,"horizontalAccuracy":8}
        """
        let point = try JSONDecoder().decode(RunRoutePoint.self, from: Data(pointJSON.utf8))
        XCTAssertNil(point.startsNewSegment)

        let runJSON = """
        {"id":"6F1B8F8E-3B0B-4D4B-9C57-0C3B6F6F0002","source":"RunSmart","startedAt":1000,"endedAt":2000,"distanceMeters":5000,"movingTimeSeconds":1000,"averagePaceSecondsPerKm":200,"routePoints":[\(pointJSON)]}
        """
        let run = try JSONDecoder().decode(RecordedRun.self, from: Data(runJSON.utf8))
        XCTAssertNil(run.pauseIntervals)
        XCTAssertEqual(run.routePoints.count, 1)

        let checkpointJSON = """
        {"schemaVersion":1,"startedAt":1000,"accumulatedPausedSeconds":0,"wasPaused":false,"routePoints":[\(pointJSON)],"distanceMeters":10,"savedAt":1500}
        """
        let checkpoint = try JSONDecoder().decode(RunSessionCheckpoint.self, from: Data(checkpointJSON.utf8))
        XCTAssertNil(checkpoint.pauseIntervals)
        XCTAssertTrue(checkpoint.isConsistent)
    }

    func testNewFieldsRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var run = RecordedRun(
            id: UUID(),
            providerActivityID: nil,
            source: .runSmart,
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            distanceMeters: 1_000,
            movingTimeSeconds: 500,
            averagePaceSecondsPerKm: 500,
            averageHeartRateBPM: nil,
            routePoints: [routePoint(metersNorth: 0, at: start, newSegment: true)],
            syncedAt: nil
        )
        run.pauseIntervals = [RunPauseInterval(start: start.addingTimeInterval(100), end: start.addingTimeInterval(200))]

        let decoded = try JSONDecoder().decode(RecordedRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(decoded, run)
        XCTAssertEqual(decoded.routePoints.first?.startsNewSegment, true)
        XCTAssertEqual(decoded.pauseIntervals?.count, 1)
    }
}
