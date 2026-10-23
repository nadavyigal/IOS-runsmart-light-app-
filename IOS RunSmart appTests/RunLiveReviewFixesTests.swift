import XCTest
import CoreLocation
@testable import IOS_RunSmart_app

/// Live-run review findings on PR 164: guide clock after auto-pause, recovery steps, one mute,
/// cue debounce, cues after discard, server cue interval, recovery parsing, map follow, current pace.
@MainActor
final class RunLiveReviewFixesTests: XCTestCase {
    private var directory: URL!
    private var savedCueSettings: RunCueSettings!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-live-review-\(UUID().uuidString)", isDirectory: true)
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

    private func deliver(_ recorder: RunRecorder, origin: Date, _ seconds: Double, speed: Double) {
        let stamp = origin.addingTimeInterval(seconds)
        recorder.handleLocationUpdates([fix(0, at: stamp, speed: speed)], now: stamp)
    }

    // MARK: 1. Guide clock after auto-pause

    func testRebaseMovesTheGuideClockBackSoATimedStepDoesNotRunLong() throws {
        var guide = try XCTUnwrap(WorkoutGuide(steps: [
            GuideStep(kind: .work, target: .duration(seconds: 60))
        ]))
        _ = guide.update(distance: 100, movingTime: 55)
        XCTAssertEqual(try XCTUnwrap(guide.progress).remainingSeconds ?? -1, 5, accuracy: 0.01)

        // The recorder backdated an auto-pause by 8 s and trimmed 12 m of drift.
        guide.rebase(distance: 88, movingTime: 47)
        _ = guide.update(distance: 88, movingTime: 47)

        XCTAssertEqual(try XCTUnwrap(guide.progress).remainingSeconds ?? -1, 13, accuracy: 0.01)
        XCTAssertFalse(guide.isFinished)
    }

    func testRebaseNeverLeavesAStepStartingAfterTheClock() throws {
        var guide = try XCTUnwrap(WorkoutGuide(steps: [
            GuideStep(kind: .work, target: .duration(seconds: 40)),
            GuideStep(kind: .recovery, target: .duration(seconds: 60))
        ]))
        _ = guide.update(distance: 120, movingTime: 42)
        XCTAssertEqual(guide.currentIndex, 1)
        XCTAssertEqual(guide.starts.last?.movingTime ?? -1, 40, accuracy: 0.01)

        guide.rebase(distance: 100, movingTime: 36)

        XCTAssertEqual(guide.starts.last?.movingTime ?? -1, 36, accuracy: 0.01)
        XCTAssertEqual(guide.starts.last?.distance ?? -1, 100, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(guide.progress).remainingSeconds ?? -1, 60, accuracy: 0.01)
    }

    func testAutoPauseRebasesTheRecorderGuideToTheBackdatedClock() throws {
        let recorder = makeRecorder()
        // In the past, so the real-time tick inside the pause matches the fix timestamps.
        let origin = Date().addingTimeInterval(-300)
        recorder.activeGuideSteps = [GuideStep(kind: .work, target: .duration(seconds: 600))]
        LocalRunCueService.shared.speechHandler = { _ in }
        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.startWithoutFix(now: origin)
        defer { recorder.discard() }

        deliver(recorder, origin: origin, 130, speed: 0)
        for second in stride(from: 131.0, through: 139, by: 1) {
            deliver(recorder, origin: origin, second, speed: 0)
        }
        XCTAssertEqual(recorder.phase, .paused)
        XCTAssertTrue(recorder.isAutoPaused)

        // The stop began at 131 s, so moving time is 131 s, not the 138 s the guide last saw.
        XCTAssertEqual(recorder.movingSeconds, 131, accuracy: 0.5)
        let guide = try XCTUnwrap(recorder.workoutGuide)
        XCTAssertEqual(guide.last.movingTime, recorder.movingSeconds, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(guide.progress).remainingSeconds ?? -1, 600 - recorder.movingSeconds, accuracy: 0.01)
    }

    // MARK: 2. Recovery step never auto-pauses

    func testStandingInARecoveryStepDoesNotAutoPause() {
        let recorder = makeRecorder()
        let origin = Date().addingTimeInterval(-300)
        recorder.activeGuideSteps = [GuideStep(kind: .recovery, target: .duration(seconds: 600))]
        LocalRunCueService.shared.speechHandler = { _ in }
        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.startWithoutFix(now: origin)
        defer { recorder.discard() }

        deliver(recorder, origin: origin, 130, speed: 0)
        for second in stride(from: 131.0, through: 160, by: 1) {
            deliver(recorder, origin: origin, second, speed: 0)
        }

        XCTAssertEqual(recorder.phase, .recording, "standing still in a recovery step is part of the workout")
        XCTAssertFalse(recorder.isAutoPaused)
    }

    func testStandingInAWorkStepStillAutoPauses() {
        let recorder = makeRecorder()
        let origin = Date().addingTimeInterval(-300)
        recorder.activeGuideSteps = [GuideStep(kind: .work, target: .duration(seconds: 600))]
        LocalRunCueService.shared.speechHandler = { _ in }
        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.startWithoutFix(now: origin)
        defer { recorder.discard() }

        deliver(recorder, origin: origin, 130, speed: 0)
        for second in stride(from: 131.0, through: 140, by: 1) {
            deliver(recorder, origin: origin, second, speed: 0)
        }

        XCTAssertEqual(recorder.phase, .paused)
    }

    // MARK: 3. One mute for local and server cues

    func testMutingSpokenCuesSilencesTheServerVoiceCueToo() {
        let coach = VoiceCoachService.shared
        let wasEnabled = coach.isEnabled
        defer {
            coach.stopSession()
            coach.setEnabled(wasEnabled)
        }
        coach.setEnabled(true)
        coach.startSession()
        XCTAssertTrue(coach.isActive)
        let generation = coach.sessionGeneration

        LocalRunCueService.shared.setEnabled(false)

        XCTAssertFalse(coach.isActive, "the Muted button must stop the server cue as well")
        XCTAssertNotEqual(coach.sessionGeneration, generation, "a cue already on its way is dropped")
        LocalRunCueService.shared.setEnabled(true)
        XCTAssertTrue(coach.isActive, "unmuting brings back the cues the runner had switched on")
    }

    func testServerCuesStayOffForARunnerWhoNeverSwitchedThemOn() {
        let coach = VoiceCoachService.shared
        let wasEnabled = coach.isEnabled
        defer { coach.setEnabled(wasEnabled) }
        coach.setEnabled(false)

        LocalRunCueService.shared.setEnabled(true)

        XCTAssertFalse(coach.isActive, "unmuting must not turn on the optional AI cue")
    }

    // MARK: 4. Queued, debounced pause announcements

    func testDebouncerDropsTheSameKindWithinTwentySeconds() {
        var debouncer = RunCueDebouncer()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(debouncer.allows(.autoPause, at: start))
        XCTAssertFalse(debouncer.allows(.autoPause, at: start.addingTimeInterval(19)))
        XCTAssertTrue(debouncer.allows(.autoResume, at: start.addingTimeInterval(5)), "kinds are independent")
        XCTAssertTrue(debouncer.allows(.autoPause, at: start.addingTimeInterval(20)))
        debouncer.reset()
        XCTAssertTrue(debouncer.allows(.autoPause, at: start.addingTimeInterval(21)))
    }

    func testAnnounceSpeaksADebouncedKindOnlyOncePerTwentySeconds() {
        var spoken: [String] = []
        let service = LocalRunCueService.shared
        service.speechHandler = { spoken.append($0) }
        service.begin()  // resets the debouncer
        spoken.removeAll()
        let now = Date()

        service.announce("Auto-paused.", queued: true, debounce: .autoPause, now: now)
        service.announce("Auto-paused.", queued: true, debounce: .autoPause, now: now.addingTimeInterval(10))
        service.announce("Run resumed.", queued: true, debounce: .autoResume, now: now.addingTimeInterval(11))
        service.announce("Auto-paused.", queued: true, debounce: .autoPause, now: now.addingTimeInterval(21))
        service.announce("Run paused.", queued: true)
        service.announce("Run paused.", queued: true)

        XCTAssertEqual(spoken, ["Auto-paused.", "Run resumed.", "Auto-paused.", "Run paused.", "Run paused."])
    }

    // MARK: 5. No cue after discard

    func testDiscardSpeaksNothingAfterTrackingStops() {
        var spoken: [String] = []
        LocalRunCueService.shared.speechHandler = { spoken.append($0) }
        let recorder = makeRecorder()
        // A warm-up that ended 5 s ago: the tick inside discard would announce the next step.
        let origin = Date().addingTimeInterval(-10)
        recorder.activeGuideSteps = [
            GuideStep(kind: .warmup, target: .duration(seconds: 5)),
            GuideStep(kind: .work, target: .duration(seconds: 60))
        ]
        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.startWithoutFix(now: origin)
        XCTAssertEqual(recorder.phase, .recording)
        let spokenBeforeDiscard = spoken

        recorder.discard()

        XCTAssertEqual(spoken, spokenBeforeDiscard, "a discarded run must not announce a step")
        XCTAssertNotEqual(recorder.phase, .recording)
    }

    func testTickWithoutCuesNeverSpeaks() {
        var spoken: [String] = []
        LocalRunCueService.shared.speechHandler = { spoken.append($0) }
        let recorder = makeRecorder()
        let origin = Date().addingTimeInterval(-10)
        recorder.activeGuideSteps = [
            GuideStep(kind: .warmup, target: .duration(seconds: 5)),
            GuideStep(kind: .work, target: .duration(seconds: 60))
        ]
        recorder.startAcquiringLocation(startLocationUpdates: false)
        recorder.startWithoutFix(now: origin)
        defer { recorder.discard() }
        let spokenBefore = spoken

        recorder.tick(now: origin.addingTimeInterval(8), allowsCues: false)
        XCTAssertEqual(spoken, spokenBefore)

        recorder.tick(now: origin.addingTimeInterval(9))
        XCTAssertEqual(spoken.count, spokenBefore.count + 1, "the same tick speaks the step cue when cues are allowed")
    }

    // MARK: 6. Server cue interval survives pause and resume

    func testServerCueIntervalContinuesAcrossPauseAndResume() {
        let coach = VoiceCoachService.shared
        let wasEnabled = coach.isEnabled
        defer {
            coach.stopSession()
            coach.setEnabled(wasEnabled)
        }
        let t0 = Date(timeIntervalSince1970: 50_000)
        coach.setEnabled(true)
        coach.startSession(now: t0)
        XCTAssertEqual(coach.cueSecondsRemaining, 300, accuracy: 0.01)

        coach.pauseSession(now: t0.addingTimeInterval(100))
        XCTAssertEqual(coach.cueSecondsRemaining, 200, accuracy: 0.01)

        // A long stop does not count as run time.
        coach.resumeSession(now: t0.addingTimeInterval(500))
        XCTAssertTrue(coach.isCueTimerRunning)
        coach.pauseSession(now: t0.addingTimeInterval(550))
        XCTAssertEqual(coach.cueSecondsRemaining, 150, accuracy: 0.01, "each resume continues the interval instead of restarting 300 s")

        coach.stopSession(now: t0.addingTimeInterval(600))
        XCTAssertEqual(coach.cueSecondsRemaining, 300, accuracy: 0.01, "a new run starts a full interval")
    }

    // MARK: 7. Recovery parsing

    func testRecoveryIgnoresWarmupAndCooldownClauses() {
        XCTAssertEqual(
            StructuredWorkoutFactory.parseRecovery(from: "10 min easy jog warm-up, 6x400m, 90 s walk recovery"),
            .duration(seconds: 90)
        )
        XCTAssertNil(StructuredWorkoutFactory.parseRecovery(from: "10 min easy jog warm-up, 6x400m at 5k pace"))
        XCTAssertNil(StructuredWorkoutFactory.parseRecovery(from: "6x400m, 10 min jog cooldown"))
        XCTAssertNil(StructuredWorkoutFactory.parseRecovery(from: "10 min walk cool down, 6x400m"))
        XCTAssertEqual(
            StructuredWorkoutFactory.parseRecovery(from: "Warm up 10 min easy, 6 x 400 m with 60 s recovery, cool down 5 min"),
            .duration(seconds: 60)
        )
    }

    // MARK: 9. Live map follow

    private func northPoints(count: Int, spacing: Double, startLatitude: Double = 32) -> [RunRoutePoint] {
        (0..<count).map { index in
            RunRoutePoint(
                latitude: startLatitude + Double(index) * spacing / 111_000,
                longitude: 34,
                timestamp: Date(timeIntervalSince1970: 1_000 + Double(index)),
                horizontalAccuracy: 5
            )
        }
    }

    func testMapHeadingIgnoresASidewaysJitterOnTheLastFix() throws {
        var points = northPoints(count: 20, spacing: 3)
        // The last fix jumps 3 m east; a two-point bearing would swing about 45 degrees.
        points[points.count - 1].longitude += 3 / (111_000 * cos(32 * .pi / 180))
        let target = try XCTUnwrap(LiveRunMapPresentation.target(for: points))
        let swing = min(target.heading, 360 - target.heading)
        XCTAssertLessThan(swing, 8, "the bearing is measured over the last ~30 m of path")
    }

    func testMapKeepsThePreviousHeadingUntilTheRunnerHasMoved() throws {
        let nearlyStill = northPoints(count: 4, spacing: 2)  // 6 m of path
        XCTAssertNil(LiveRunMapPresentation.heading(for: nearlyStill))
        let held = try XCTUnwrap(LiveRunMapPresentation.target(for: nearlyStill, previousHeading: 123))
        XCTAssertEqual(held.heading, 123)

        let moved = northPoints(count: 8, spacing: 2)  // 14 m
        XCTAssertNotNil(LiveRunMapPresentation.heading(for: moved))
        let updated = try XCTUnwrap(LiveRunMapPresentation.target(for: moved, previousHeading: 123))
        XCTAssertEqual(updated.heading, 0, accuracy: 0.5)
    }

    func testMapRemembersARunnersZoomButNotTheAutomaticCamera() {
        XCTAssertEqual(LiveRunMapPresentation.rememberedDistance(from: 350, current: 800), 350)
        XCTAssertEqual(LiveRunMapPresentation.rememberedDistance(from: 4_000_000, current: 800), 800)
        XCTAssertEqual(LiveRunMapPresentation.rememberedDistance(from: 0, current: 350), 350)
    }

    // MARK: 10. Current pace after a GPS gap

    private func routePoint(metersNorth: Double, at stamp: Date) -> RunRoutePoint {
        RunRoutePoint(
            latitude: 32 + metersNorth / 111_000,
            longitude: 34,
            timestamp: stamp,
            horizontalAccuracy: 5
        )
    }

    func testCurrentPaceIsNilForAFixThatArrivesMinutesAfterThePreviousOne() {
        let start = Date(timeIntervalSince1970: 20_000)
        // 100 m at 5:00/km, then no fix for 5 minutes and one fix 300 m further on.
        var points = (0...10).map { routePoint(metersNorth: Double($0) * 10, at: start.addingTimeInterval(Double($0) * 3)) }
        points.append(routePoint(metersNorth: 400, at: start.addingTimeInterval(30 + 300)))

        XCTAssertNil(RunRecorder.currentPace(points: points, now: start.addingTimeInterval(331)),
                     "one fix is not 10 s of history, and the gap's average pace is not the current pace")
    }

    func testCurrentPaceAfterAGapUsesOnlyInWindowFixes() throws {
        let start = Date(timeIntervalSince1970: 20_000)
        var points = (0...10).map { routePoint(metersNorth: Double($0) * 10, at: start.addingTimeInterval(Double($0) * 3)) }
        let resume = start.addingTimeInterval(330)
        // Back to 5:00/km (10 m every 3 s) for 15 s after the gap.
        points += (0...5).map { routePoint(metersNorth: 400 + Double($0) * 10, at: resume.addingTimeInterval(Double($0) * 3)) }

        let pace = try XCTUnwrap(RunRecorder.currentPace(points: points, now: resume.addingTimeInterval(16)))
        XCTAssertEqual(pace, 300, accuracy: 6, "the 300 s gap must not leak into the window")
    }

    func testCurrentPaceClipsTheSegmentThatCrossesTheWindowStart() throws {
        let start = Date(timeIntervalSince1970: 20_000)
        // Fixes every 8 s. The 48 s to 56 s segment covers 100 m and straddles the window start
        // (newest 80 s, window 50 s), so only 6/8 of it, 75 m, belongs to the window.
        let unit = 80.0 / 3  // 8 s at 5:00/km
        var meters: [Double] = (0...6).map { Double($0) * unit }
        meters += (7...10).map { meters[6] + 100 + Double($0 - 7) * unit }
        let points = meters.enumerated().map { routePoint(metersNorth: $0.element, at: start.addingTimeInterval(Double($0.offset) * 8)) }

        let pace = try XCTUnwrap(RunRecorder.currentPace(points: points, now: start.addingTimeInterval(81)))

        XCTAssertEqual(pace, 30 / 0.155, accuracy: 1, "75 m clipped from the boundary segment plus 80 m in the window, over 30 s")
    }
}
