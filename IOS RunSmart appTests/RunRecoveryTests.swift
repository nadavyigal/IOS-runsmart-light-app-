import XCTest
import CoreLocation
@testable import IOS_RunSmart_app

/// Crash and kill recovery (record-run plan S1). Every test injects a checkpoint store
/// backed by its own temp directory, so nothing here touches the real Application Support.
@MainActor
final class RunRecoveryTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-recovery-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        RunCheckpointStore.flush()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Helpers

    private var checkpointStore: RunCheckpointStore { RunCheckpointStore(directoryURL: directory) }

    private var checkpointFile: URL {
        directory.appendingPathComponent(RunCheckpointStore.fileName)
    }

    /// Checkpoint writes are asynchronous; wait for them before looking at the file.
    private func checkpointFileExists() -> Bool {
        RunCheckpointStore.flush()
        return FileManager.default.fileExists(atPath: checkpointFile.path)
    }

    private func makeRecorder(status: CLAuthorizationStatus = .authorizedWhenInUse) -> RunRecorder {
        let recorder = RunRecorder(store: .shared, checkpointStore: checkpointStore)
        recorder.authorizationStatusProvider = { status }
        return recorder
    }

    private func makeLocation(latitude: Double, timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 34.78),
            altitude: 0,
            horizontalAccuracy: 8,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
    }

    /// Starts a run and feeds it two fixes about 33 m apart.
    private func recordShortRun(_ recorder: RunRecorder, now: Date = Date()) {
        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.handleLocationUpdates([makeLocation(latitude: 32.0800, timestamp: now)], now: now)
        let later = now.addingTimeInterval(5)
        recorder.handleLocationUpdates([makeLocation(latitude: 32.0803, timestamp: later)], now: later)
    }

    private func makeCheckpoint(
        startedAgo: TimeInterval = 600,
        savedAgo: TimeInterval = 120,
        wasPaused: Bool = false
    ) -> RunSessionCheckpoint {
        let now = Date()
        let start = now.addingTimeInterval(-startedAgo)
        let points = (0..<3).map { index in
            RunRoutePoint(
                latitude: 32.08 + Double(index) * 0.0003,
                longitude: 34.78,
                timestamp: start.addingTimeInterval(Double(index) * 5),
                horizontalAccuracy: 8,
                altitude: nil
            )
        }
        return RunSessionCheckpoint(
            startedAt: start,
            accumulatedPausedSeconds: wasPaused ? 60 : 0,
            pausedAt: wasPaused ? now.addingTimeInterval(-savedAgo - 30) : nil,
            wasPaused: wasPaused,
            routePoints: points,
            distanceMeters: 5_210,
            workoutTitle: "Tempo Run",
            savedAt: now.addingTimeInterval(-savedAgo)
        )
    }

    // MARK: Checkpoint and store

    func testCheckpointJSONRoundTripKeepsEveryField() throws {
        let checkpoint = makeCheckpoint(wasPaused: true)

        let data = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(RunSessionCheckpoint.self, from: data)

        XCTAssertEqual(decoded, checkpoint)
        XCTAssertEqual(decoded.schemaVersion, RunSessionCheckpoint.currentSchemaVersion)
    }

    func testCheckpointStoreSavesLoadsAndDeletes() {
        let store = checkpointStore
        let checkpoint = makeCheckpoint()

        XCTAssertNil(store.load())
        store.save(checkpoint)
        XCTAssertEqual(store.load(), checkpoint)
        store.delete()
        XCTAssertNil(store.load())
        XCTAssertFalse(checkpointFileExists())
    }

    func testCheckpointStoreDropsUnknownSchemaInconsistentAndCorruptFiles() throws {
        let store = checkpointStore

        var futureSchema = makeCheckpoint()
        futureSchema.schemaVersion = RunSessionCheckpoint.currentSchemaVersion + 1
        store.save(futureSchema)
        XCTAssertNil(store.load())
        XCTAssertFalse(checkpointFileExists(), "unknown schema must be deleted")

        var startsAfterSave = makeCheckpoint()
        startsAfterSave.startedAt = startsAfterSave.savedAt.addingTimeInterval(60)
        store.save(startsAfterSave)
        XCTAssertNil(store.load())
        XCTAssertFalse(checkpointFileExists(), "startedAt after savedAt must be deleted")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: checkpointFile)
        XCTAssertNil(store.load())
        XCTAssertFalse(checkpointFileExists(), "corrupt file must be deleted")
    }

    func testDeleteIssuedAfterWritesIsNeverOvertaken() {
        let store = checkpointStore
        let checkpoint = makeCheckpoint()

        for _ in 0..<50 {
            store.save(checkpoint)
            store.delete()
        }

        XCTAssertFalse(checkpointFileExists())
        XCTAssertNil(store.load())
    }

    func testInertCheckpointStoreNeverWrites() {
        let inert = RunCheckpointStore(directoryURL: nil)
        inert.save(makeCheckpoint())
        XCTAssertNil(inert.load())
    }

    // MARK: Writing from the recorder

    func testImmediateGPSStartRecoveryKeepsPlannedWorkoutGuide() throws {
        let first = makeRecorder()
        first.activeWorkoutTitle = "Intervals"
        let steps = [GuideStep(kind: .work, target: .duration(seconds: 60)),
                     GuideStep(kind: .recovery, target: .duration(seconds: 30))]
        first.activeGuideSteps = steps
        first.startAcquiringLocation(startLocationUpdates: false)
        let now = Date()
        first.handleLocationUpdates([makeLocation(latitude: 32.0800, timestamp: now)], now: now)
        defer { first.discard() }

        let checkpoint = try XCTUnwrap(checkpointStore.load())
        let savedGuide = try XCTUnwrap(checkpoint.workoutGuide,
                                      "The very first checkpoint must contain interval guidance")
        XCTAssertEqual(savedGuide.steps, steps)
        let relaunched = makeRecorder()
        defer { relaunched.discard() }
        relaunched.resumeRecoveredRun(startLocationUpdates: false)
        XCTAssertEqual(relaunched.phase, .paused)
        XCTAssertEqual(relaunched.workoutGuide?.steps, steps)
        XCTAssertEqual(relaunched.activeWorkoutTitle, "Intervals")
    }

    func testCheckpointIsWrittenWhenRecordingBeginsAndOnPauseAndResume() throws {
        let recorder = makeRecorder()
        recorder.activeWorkoutTitle = "Easy Run"
        recordShortRun(recorder)
        defer { recorder.discard() }

        let recording = try XCTUnwrap(checkpointStore.load(), "the first accepted fix writes the opening checkpoint")
        XCTAssertFalse(recording.wasPaused)
        XCTAssertEqual(recording.workoutTitle, "Easy Run")
        XCTAssertGreaterThanOrEqual(recording.routePoints.count, 1)

        recorder.pause()
        let paused = try XCTUnwrap(checkpointStore.load())
        XCTAssertTrue(paused.wasPaused)
        XCTAssertNotNil(paused.pausedAt)
        XCTAssertEqual(paused.routePoints.count, 2)
        XCTAssertEqual(paused.distanceMeters, recorder.distanceMeters, accuracy: 0.001)

        recorder.resume()
        let resumed = try XCTUnwrap(checkpointStore.load())
        XCTAssertFalse(resumed.wasPaused)
        XCTAssertNil(resumed.pausedAt)
    }

    func testCheckpointWritesFromLocationsAreThrottledToTenSeconds() throws {
        let recorder = makeRecorder()
        let now = Date()
        recordShortRun(recorder, now: now)  // fixes at +0 s (writes) and +5 s (throttled)
        defer { recorder.discard() }

        XCTAssertEqual(try XCTUnwrap(checkpointStore.load()).routePoints.count, 1)

        let third = now.addingTimeInterval(12)
        recorder.handleLocationUpdates([makeLocation(latitude: 32.0806, timestamp: third)], now: third)
        XCTAssertEqual(try XCTUnwrap(checkpointStore.load()).routePoints.count, 3)
    }

    func testFinishDeletesCheckpoint() {
        let recorder = makeRecorder()
        recordShortRun(recorder)
        XCTAssertTrue(checkpointFileExists())

        let run = recorder.finish()
        defer { if let run { RunSmartLocalStore.shared.removeRun(run) } }

        XCTAssertNotNil(run)
        XCTAssertFalse(checkpointFileExists())
        XCTAssertNil(checkpointStore.load())
    }

    func testDiscardDeletesCheckpoint() {
        let recorder = makeRecorder()
        recordShortRun(recorder)
        recorder.pause()
        XCTAssertTrue(checkpointFileExists())

        recorder.discard()

        XCTAssertFalse(checkpointFileExists())
        XCTAssertEqual(recorder.phase, .ready)
    }

    // MARK: Recovery

    func testNewRecorderOnSameDirectoryExposesPendingRecovery() {
        let first = makeRecorder()
        recordShortRun(first)
        first.pause()
        let saved = checkpointStore.load()
        XCTAssertNotNil(saved)

        // Simulates the relaunch after a kill: the old instance is simply gone.
        let relaunched = makeRecorder()

        XCTAssertEqual(relaunched.pendingRecovery, saved)
        XCTAssertNotEqual(relaunched.phase, .recording)
        XCTAssertNotEqual(relaunched.phase, .paused)
        first.discard()
        relaunched.discardRecoveredRun()
    }

    func testRecorderWithoutCheckpointHasNoPendingRecovery() {
        XCTAssertNil(makeRecorder().pendingRecovery)
    }

    func testResumeRecoveredRunRestoresRunAsPausedAndCountsTheGapAsPausedTime() throws {
        let checkpoint = makeCheckpoint(startedAgo: 600, savedAgo: 120)
        checkpointStore.save(checkpoint)
        let recorder = makeRecorder()
        defer { recorder.discard() }

        XCTAssertTrue(recorder.canResumeRecoveredRun)
        recorder.resumeRecoveredRun(startLocationUpdates: false)

        XCTAssertEqual(recorder.phase, .paused)
        XCTAssertNil(recorder.pendingRecovery)
        XCTAssertEqual(recorder.distanceMeters, 5_210, accuracy: 0.001)
        XCTAssertEqual(recorder.routePoints, checkpoint.routePoints)
        XCTAssertEqual(recorder.displayRoutePoints, checkpoint.routePoints)
        XCTAssertEqual(recorder.activeWorkoutTitle, "Tempo Run")
        // 600 s since start, of which the last 120 s (since savedAt) are not run time.
        XCTAssertEqual(recorder.elapsedSeconds, 600, accuracy: 2)
        XCTAssertEqual(recorder.movingSeconds, 480, accuracy: 2)
        XCTAssertNotNil(checkpointStore.load(), "the checkpoint keeps being rewritten while the run continues")
        XCTAssertEqual(try XCTUnwrap(checkpointStore.load()).wasPaused, true)
    }

    func testResumeRecoveredRunKeepsAnExistingPauseStart() {
        let checkpoint = makeCheckpoint(startedAgo: 600, savedAgo: 120, wasPaused: true)
        checkpointStore.save(checkpoint)
        let recorder = makeRecorder()
        defer { recorder.discard() }

        recorder.resumeRecoveredRun(startLocationUpdates: false)

        // Paused 150 s ago (30 s before save + 120 s since): 600 - 60 already paused - 150.
        XCTAssertEqual(recorder.phase, .paused)
        XCTAssertEqual(recorder.movingSeconds, 390, accuracy: 2)
    }

    func testLocationsReceivedWhilePausedDoNotAddDistanceOrPoints() {
        checkpointStore.save(makeCheckpoint())
        let recorder = makeRecorder()
        defer { recorder.discard() }
        recorder.resumeRecoveredRun(startLocationUpdates: false)

        let now = Date()
        recorder.handleLocationUpdates([makeLocation(latitude: 32.2, timestamp: now)], now: now)

        XCTAssertEqual(recorder.distanceMeters, 5_210, accuracy: 0.001)
        XCTAssertEqual(recorder.routePoints.count, 3)
    }

    func testResumedRunKeepsRecordingFromAFreshAnchorAfterResume() {
        checkpointStore.save(makeCheckpoint())
        let recorder = makeRecorder()
        defer { recorder.discard() }
        recorder.resumeRecoveredRun(startLocationUpdates: false)

        recorder.resume()
        XCTAssertEqual(recorder.phase, .recording)

        // The first fix after resume is a new anchor: the jump from the old position adds nothing.
        let now = Date()
        recorder.handleLocationUpdates([makeLocation(latitude: 32.2, timestamp: now)], now: now)
        XCTAssertEqual(recorder.distanceMeters, 5_210, accuracy: 0.001)
        XCTAssertEqual(recorder.routePoints.count, 4)
    }

    func testSaveRecoveredRunStoresCheckpointDistanceAndDeletesFile() throws {
        let checkpoint = makeCheckpoint(startedAgo: 600, savedAgo: 120)
        checkpointStore.save(checkpoint)
        let recorder = makeRecorder()

        let run = try XCTUnwrap(recorder.saveRecoveredRun())
        defer { RunSmartLocalStore.shared.removeRun(run) }

        XCTAssertEqual(run.distanceMeters, 5_210, accuracy: 0.001)
        XCTAssertEqual(run.startedAt, checkpoint.startedAt)
        XCTAssertEqual(run.endedAt, checkpoint.savedAt, "the last route point is older than savedAt")
        XCTAssertEqual(run.movingTimeSeconds, 480, accuracy: 0.001)
        XCTAssertEqual(run.routePoints, checkpoint.routePoints)
        XCTAssertEqual(recorder.lastSavedRun?.id, run.id)
        XCTAssertNil(recorder.pendingRecovery)
        XCTAssertEqual(recorder.phase, .ready)
        XCTAssertFalse(checkpointFileExists())
        XCTAssertTrue(RunSmartLocalStore.shared.loadRuns().contains { $0.id == run.id })
    }

    func testSaveRecoveredRunSubtractsAnOpenPauseFromMovingTime() throws {
        let checkpoint = makeCheckpoint(startedAgo: 600, savedAgo: 120, wasPaused: true)
        checkpointStore.save(checkpoint)

        let run = try XCTUnwrap(makeRecorder().saveRecoveredRun())
        defer { RunSmartLocalStore.shared.removeRun(run) }

        // Ended at savedAt (120 s ago): 480 s since start, 60 s paused earlier, 30 s into a pause.
        XCTAssertEqual(run.movingTimeSeconds, 390, accuracy: 0.001)
    }

    func testDiscardRecoveredRunDeletesCheckpointAndClearsPrompt() {
        checkpointStore.save(makeCheckpoint())
        let recorder = makeRecorder()
        XCTAssertNotNil(recorder.pendingRecovery)

        recorder.discardRecoveredRun()

        XCTAssertNil(recorder.pendingRecovery)
        XCTAssertFalse(checkpointFileExists())
        XCTAssertNil(makeRecorder().pendingRecovery)
    }

    func testCheckpointOlderThanTwelveHoursCannotResumeButCanBeSaved() throws {
        checkpointStore.save(makeCheckpoint(startedAgo: 13 * 3_600 + 600, savedAgo: 13 * 3_600))
        let recorder = makeRecorder()

        XCTAssertNotNil(recorder.pendingRecovery)
        XCTAssertFalse(recorder.canResumeRecoveredRun)
        recorder.resumeRecoveredRun(startLocationUpdates: false)
        XCTAssertNotNil(recorder.pendingRecovery, "a refused resume leaves the prompt in place")
        XCTAssertNotEqual(recorder.phase, .paused)

        let run = try XCTUnwrap(recorder.saveRecoveredRun())
        RunSmartLocalStore.shared.removeRun(run)
    }

    func testResumeIsNotOfferedWithoutLocationPermission() {
        checkpointStore.save(makeCheckpoint())
        let recorder = makeRecorder(status: .denied)

        XCTAssertNotNil(recorder.pendingRecovery)
        XCTAssertFalse(recorder.canResumeRecoveredRun)
        recorder.discardRecoveredRun()
    }

    func testStartingANewRunSavesAnUnansweredRecoveryInsteadOfOverwritingIt() throws {
        let checkpoint = makeCheckpoint()
        checkpointStore.save(checkpoint)
        let recorder = makeRecorder()
        defer { recorder.discard() }

        recorder.startAcquiringLocation(startLocationUpdates: false)

        XCTAssertNil(recorder.pendingRecovery)
        let saved = try XCTUnwrap(recorder.lastSavedRun)
        defer { RunSmartLocalStore.shared.removeRun(saved) }
        XCTAssertEqual(saved.distanceMeters, 5_210, accuracy: 0.001)
        XCTAssertEqual(recorder.phase, .acquiringLocation)
    }

    // MARK: Release A review fixes

    func testPermissionDeniedMidRunKeepsTheRunForTheRecoveryPrompt() throws {
        let recorder = makeRecorder()
        recordShortRun(recorder)
        let distance = recorder.distanceMeters
        XCTAssertGreaterThan(distance, 20)

        recorder.authorizationStatusProvider = { .denied }
        recorder.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))

        XCTAssertEqual(recorder.phase, .denied)
        let pending = try XCTUnwrap(recorder.pendingRecovery, "the prompt must offer Save or Discard")
        XCTAssertEqual(pending.distanceMeters, distance, accuracy: 0.001)
        XCTAssertEqual(pending.routePoints.count, 2)
        XCTAssertFalse(recorder.canResumeRecoveredRun, "resume is withheld without permission")
        RunCheckpointStore.flush()
        XCTAssertNotNil(checkpointStore.load(), "a later Start must not find an empty disk")

        let run = try XCTUnwrap(recorder.saveRecoveredRun())
        defer { RunSmartLocalStore.shared.removeRun(run) }
        XCTAssertEqual(run.distanceMeters, distance, accuracy: 0.001)
        XCTAssertEqual(run.routePoints.count, 2)
        XCTAssertNil(recorder.pendingRecovery)
    }

    func testFinishAndSaveRecoveredRunDeleteTheCheckpointBeforeReturning() throws {
        let recorder = makeRecorder()
        recordShortRun(recorder)
        XCTAssertTrue(checkpointFileExists())

        let finished = try XCTUnwrap(recorder.finish())
        defer { RunSmartLocalStore.shared.removeRun(finished) }
        // No flush: a kill right after finish() must not find the file.
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpointFile.path))

        checkpointStore.save(makeCheckpoint())
        let relaunched = makeRecorder()
        XCTAssertNotNil(relaunched.pendingRecovery)
        let saved = try XCTUnwrap(relaunched.saveRecoveredRun())
        defer { RunSmartLocalStore.shared.removeRun(saved) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpointFile.path))
    }

    func testCompletedKilometerSplitsAreCachedAndAppearAfterTheFirstKilometer() {
        let recorder = makeRecorder()
        let now = Date()
        recorder.startAcquiringLocation(startLocationUpdates: false)
        defer { recorder.discard() }

        let fixes: [(Double, TimeInterval)] = [(32.0000, 0), (32.0045, 150), (32.0095, 300)]
        var counts: [Int] = []
        for (latitude, offset) in fixes {
            let time = now.addingTimeInterval(offset)
            recorder.handleLocationUpdates([makeLocation(latitude: latitude, timestamp: time)], now: time)
            counts.append(recorder.completedKilometerSplits.count)
        }

        XCTAssertEqual(counts, [0, 0, 1])
        XCTAssertEqual(recorder.completedKilometerSplits.first?.km, 1)
        XCTAssertEqual(recorder.completedKilometerSplits.first?.isPartial, false)
        XCTAssertEqual(
            recorder.completedKilometerSplits,
            RunRecorder.kilometerSplits(from: recorder.routePoints).filter { !$0.isPartial }
        )
    }
}
