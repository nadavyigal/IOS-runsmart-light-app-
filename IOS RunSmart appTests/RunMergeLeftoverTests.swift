import XCTest
import CoreLocation
@testable import IOS_RunSmart_app

/// Release A + Release B integration: Start anyway with local cues and auto-pause, and the
/// recovered-run save that happens when a new run starts.
@MainActor
final class RunMergeLeftoverTests: XCTestCase {
    private var directory: URL!
    private var savedCueSettings: RunCueSettings!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-merge-tests-\(UUID().uuidString)", isDirectory: true)
        savedCueSettings = LocalRunCueService.shared.settings
        LocalRunCueService.shared.settings = RunCueSettings()
    }

    override func tearDown() async throws {
        LocalRunCueService.shared.speechHandler = nil
        LocalRunCueService.shared.settings = savedCueSettings
        RunCheckpointStore.flush()
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeRecorder() -> RunRecorder {
        let recorder = RunRecorder(store: .shared, checkpointStore: RunCheckpointStore(directoryURL: directory))
        recorder.authorizationStatusProvider = { .authorizedWhenInUse }
        recorder.autoPauseEnabledProvider = { true }
        return recorder
    }

    private func fix(_ meters: Double, at stamp: Date, speed: Double) -> CLLocation {
        CLLocation(
            coordinate: .init(latitude: 32 + meters / 111_000, longitude: 34),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: -1,
            course: -1,
            speed: speed,
            timestamp: stamp
        )
    }

    // MARK: Start anyway

    func testStartAnywaySpeaksTheSameStartCueAsANormalStart() {
        var spoken: [String] = []
        LocalRunCueService.shared.speechHandler = { spoken.append($0) }

        let recorder = makeRecorder()
        recorder.startAcquiringLocation(startLocationUpdates: false)
        XCTAssertTrue(spoken.isEmpty, "nothing is announced while searching for GPS")
        recorder.startWithoutFix(now: Date())
        defer { recorder.discard() }

        XCTAssertEqual(spoken, ["Run started."])
    }

    func testStartAnywayCannotAutoPauseBeforeTheFirstFixThenArmsAutoPause() {
        let recorder = makeRecorder()
        let origin = Date()
        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.startWithoutFix(now: origin)
        defer { recorder.discard() }

        // Two minutes with no fix at all: the clock runs, the run stays recording.
        for second in stride(from: 1.0, through: 120, by: 1) {
            recorder.tick(now: origin.addingTimeInterval(second))
        }
        XCTAssertEqual(recorder.phase, .recording)
        XCTAssertFalse(recorder.isAutoPaused)
        XCTAssertEqual(recorder.movingSeconds, 120, accuracy: 0.01)

        // The first fix is recorded without being judged; auto-pause then works as usual.
        func deliver(_ seconds: Double, speed: Double) {
            let stamp = origin.addingTimeInterval(seconds)
            recorder.handleLocationUpdates([fix(0, at: stamp, speed: speed)], now: stamp)
        }
        deliver(130, speed: 0)
        XCTAssertEqual(recorder.routePoints.count, 1)
        XCTAssertEqual(recorder.phase, .recording)
        deliver(131, speed: 0)
        deliver(138, speed: 0)
        XCTAssertEqual(recorder.phase, .recording, "seven seconds of stillness is not a stop yet")
        deliver(139, speed: 0)
        XCTAssertEqual(recorder.phase, .paused)
        XCTAssertTrue(recorder.isAutoPaused)
    }

    // MARK: Recovered run saved by starting a new run

    func testStartingANewRunKeepsItsTitleAndHandsTheRecoveredRunToTheOwner() throws {
        let store = RunCheckpointStore(directoryURL: directory)
        let now = Date()
        let start = now.addingTimeInterval(-900)
        let points = (0..<3).map { index in
            RunRoutePoint(
                latitude: 32.08 + Double(index) * 0.0003,
                longitude: 34.78,
                timestamp: start.addingTimeInterval(Double(index) * 5),
                horizontalAccuracy: 8,
                altitude: nil
            )
        }
        store.save(RunSessionCheckpoint(
            startedAt: start,
            accumulatedPausedSeconds: 0,
            pausedAt: nil,
            wasPaused: false,
            routePoints: points,
            distanceMeters: 3_000,
            workoutTitle: "Old Tempo",
            savedAt: now.addingTimeInterval(-300)
        ))
        RunCheckpointStore.flush()

        let recorder = makeRecorder()
        XCTAssertNotNil(recorder.pendingRecovery)
        var handedOver: [RecordedRun] = []
        recorder.onRecoveredRunAutoSaved = { handedOver.append($0) }
        defer { recorder.discard() }

        recorder.activeWorkoutTitle = "New Intervals"
        recorder.startAcquiringLocation(startLocationUpdates: false)

        XCTAssertEqual(recorder.activeWorkoutTitle, "New Intervals", "saving the old run must not wipe the new run's title")
        XCTAssertNil(recorder.pendingRecovery)
        XCTAssertEqual(handedOver.count, 1)
        let saved = try XCTUnwrap(handedOver.first)
        defer { RunSmartLocalStore.shared.removeRun(saved) }
        XCTAssertEqual(saved.distanceMeters, 3_000, accuracy: 0.001)
        XCTAssertEqual(recorder.phase, .acquiringLocation)
    }

    func testStartingWithoutARecoveryDoesNotCallTheHandler() {
        let recorder = makeRecorder()
        var calls = 0
        recorder.onRecoveredRunAutoSaved = { _ in calls += 1 }
        defer { recorder.discard() }

        recorder.startAcquiringLocation(startLocationUpdates: false)

        XCTAssertEqual(calls, 0)
    }
}
