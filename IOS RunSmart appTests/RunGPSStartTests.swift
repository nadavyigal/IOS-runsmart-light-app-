import XCTest
import CoreLocation
@testable import IOS_RunSmart_app

/// GPS start that never hangs (record-run plan S3). Every test injects a checkpoint store
/// backed by its own temp directory, so nothing here touches the real Application Support.
@MainActor
final class RunGPSStartTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-gps-start-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        RunCheckpointStore.flush()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Helpers

    private var checkpointStore: RunCheckpointStore { RunCheckpointStore(directoryURL: directory) }

    private func makeRecorder(status: CLAuthorizationStatus = .authorizedWhenInUse) -> RunRecorder {
        let recorder = RunRecorder(store: .shared, checkpointStore: checkpointStore)
        recorder.authorizationStatusProvider = { status }
        return recorder
    }

    private func makeLocation(latitude: Double, timestamp: Date, accuracy: Double = 8) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 34.78),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
    }

    private func startedWithoutFix(_ recorder: RunRecorder, now: Date = Date()) {
        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.startWithoutFix(now: now)
    }

    // MARK: Delay

    func testCanStartWithoutFixOnlyAfterTwentySeconds() {
        let start = Date()

        XCTAssertFalse(RunRecorder.canStartWithoutFix(acquiringSince: nil, now: start))
        XCTAssertFalse(RunRecorder.canStartWithoutFix(acquiringSince: start, now: start.addingTimeInterval(19)))
        XCTAssertTrue(RunRecorder.canStartWithoutFix(acquiringSince: start, now: start.addingTimeInterval(20)))
        XCTAssertTrue(RunRecorder.canStartWithoutFix(acquiringSince: start, now: start.addingTimeInterval(45)))
    }

    func testAcquiringPublishesStartTimeAndClearsItOnExit() {
        let recorder = makeRecorder()
        XCTAssertNil(recorder.acquiringStartedAt)

        recorder.startAcquiringLocation(startLocationUpdates: false)
        XCTAssertNotNil(recorder.acquiringStartedAt)
        XCTAssertFalse(recorder.canStartWithoutFix)

        recorder.cancelAcquiring()
        XCTAssertNil(recorder.acquiringStartedAt)
        XCTAssertFalse(recorder.canStartWithoutFix)
    }

    func testTransientLocationErrorKeepsSearchingButDeniedEndsIt() {
        let recorder = makeRecorder()
        recorder.startAcquiringLocation(startLocationUpdates: false)

        recorder.locationManager(CLLocationManager(), didFailWithError: CLError(.locationUnknown))
        XCTAssertEqual(recorder.phase, .acquiringLocation)
        XCTAssertNotNil(recorder.acquiringStartedAt)

        recorder.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))
        XCTAssertEqual(recorder.phase, .failed)
        XCTAssertNil(recorder.acquiringStartedAt)
    }

    // MARK: Cancel

    func testCancelAcquiringReturnsToReadyWithNoRoute() {
        let recorder = makeRecorder()
        recorder.startAcquiringLocation(startLocationUpdates: false)
        XCTAssertEqual(recorder.phase, .acquiringLocation)

        recorder.cancelAcquiring()

        XCTAssertEqual(recorder.phase, .ready)
        XCTAssertTrue(recorder.routePoints.isEmpty)
        XCTAssertEqual(recorder.distanceMeters, 0)
        XCTAssertNil(recorder.acquiringStartedAt)
    }

    func testCancelAcquiringIsNoOpOutsideAcquiring() {
        let recorder = makeRecorder()
        let idlePhase = recorder.phase
        recorder.cancelAcquiring()
        XCTAssertEqual(recorder.phase, idlePhase)

        startedWithoutFix(recorder)
        defer { recorder.discard() }
        recorder.cancelAcquiring()
        XCTAssertEqual(recorder.phase, .recording)
    }

    // MARK: Start without a fix

    func testStartWithoutFixRecordsAtZeroDistanceAndWritesCheckpoint() throws {
        let recorder = makeRecorder()
        recorder.activeWorkoutTitle = "Easy Run"
        let now = Date()
        startedWithoutFix(recorder, now: now)
        defer { recorder.discard() }

        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertEqual(recorder.distanceMeters, 0)
        XCTAssertTrue(recorder.routePoints.isEmpty)
        XCTAssertNil(recorder.acquiringStartedAt)
        XCTAssertFalse(recorder.canStartWithoutFix)

        RunCheckpointStore.flush()
        let checkpoint = try XCTUnwrap(checkpointStore.load(), "a crash before the first fix must be recoverable")
        XCTAssertEqual(checkpoint.startedAt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(checkpoint.routePoints.isEmpty)
        XCTAssertEqual(checkpoint.workoutTitle, "Easy Run")
        XCTAssertFalse(checkpoint.wasPaused)
    }

    func testStartWithoutFixIsNoOpOutsideAcquiring() {
        let recorder = makeRecorder()
        let idlePhase = recorder.phase
        recorder.startWithoutFix()
        XCTAssertEqual(recorder.phase, idlePhase)
        XCTAssertNotEqual(recorder.phase, .recording)
        RunCheckpointStore.flush()
        XCTAssertNil(checkpointStore.load())

        startedWithoutFix(recorder)
        defer { recorder.discard() }
        recorder.pause()
        recorder.startWithoutFix()
        XCTAssertEqual(recorder.phase, .paused)
    }

    func testFirstFixAfterStartWithoutFixAddsPointButNoDistance() {
        let recorder = makeRecorder()
        let now = Date()
        startedWithoutFix(recorder, now: now)
        defer { recorder.discard() }

        let first = now.addingTimeInterval(30)
        recorder.handleLocationUpdates([makeLocation(latitude: 32.0800, timestamp: first)], now: first)
        XCTAssertEqual(recorder.routePoints.count, 1)
        XCTAssertEqual(recorder.distanceMeters, 0)
        XCTAssertNil(recorder.routePoints.first?.startsNewSegment)

        let second = first.addingTimeInterval(5)
        recorder.handleLocationUpdates([makeLocation(latitude: 32.0803, timestamp: second)], now: second)
        XCTAssertEqual(recorder.routePoints.count, 2)
        XCTAssertGreaterThan(recorder.distanceMeters, 20)
    }

    func testWeakFixAfterStartWithoutFixIsIgnored() {
        let recorder = makeRecorder()
        let now = Date()
        startedWithoutFix(recorder, now: now)
        defer { recorder.discard() }

        let later = now.addingTimeInterval(10)
        recorder.handleLocationUpdates([makeLocation(latitude: 32.0800, timestamp: later, accuracy: 120)], now: later)

        XCTAssertTrue(recorder.routePoints.isEmpty)
        XCTAssertEqual(recorder.distanceMeters, 0)
    }

    func testFinishAfterStartWithoutFixSavesZeroMeterRun() throws {
        let recorder = makeRecorder()
        startedWithoutFix(recorder, now: Date().addingTimeInterval(-90))

        let run = try XCTUnwrap(recorder.finish())
        defer { RunSmartLocalStore.shared.removeRun(run) }

        XCTAssertEqual(run.distanceMeters, 0)
        XCTAssertTrue(run.routePoints.isEmpty)
        XCTAssertGreaterThan(run.movingTimeSeconds, 60)
        XCTAssertEqual(recorder.phase, .ready)
        RunCheckpointStore.flush()
        XCTAssertNil(checkpointStore.load())
    }

    // MARK: Recovery

    func testZeroPointCheckpointIsRecoverable() throws {
        let recorder = makeRecorder()
        startedWithoutFix(recorder, now: Date().addingTimeInterval(-120))
        RunCheckpointStore.flush()

        // A new launch after a kill: a fresh recorder reads the checkpoint from disk.
        let relaunched = makeRecorder()
        let pending = try XCTUnwrap(relaunched.pendingRecovery)
        XCTAssertTrue(pending.routePoints.isEmpty)
        XCTAssertTrue(relaunched.canResumeRecoveredRun)

        relaunched.resumeRecoveredRun(startLocationUpdates: false)
        XCTAssertEqual(relaunched.phase, .paused)
        XCTAssertTrue(relaunched.routePoints.isEmpty)

        relaunched.resume()
        let later = Date()
        relaunched.handleLocationUpdates([makeLocation(latitude: 32.0800, timestamp: later)], now: later)
        XCTAssertEqual(relaunched.routePoints.count, 1)
        XCTAssertEqual(relaunched.distanceMeters, 0)

        let run = try XCTUnwrap(relaunched.finish())
        defer { RunSmartLocalStore.shared.removeRun(run) }
        XCTAssertEqual(run.distanceMeters, 0)
    }

    func testZeroPointCheckpointCanBeSavedWithoutResuming() throws {
        let recorder = makeRecorder()
        startedWithoutFix(recorder, now: Date().addingTimeInterval(-120))
        RunCheckpointStore.flush()

        let relaunched = makeRecorder()
        let run = try XCTUnwrap(relaunched.saveRecoveredRun())
        defer { RunSmartLocalStore.shared.removeRun(run) }

        XCTAssertEqual(run.distanceMeters, 0)
        XCTAssertTrue(run.routePoints.isEmpty)
        XCTAssertNil(relaunched.pendingRecovery)
        RunCheckpointStore.flush()
        XCTAssertNil(checkpointStore.load())
    }
}
