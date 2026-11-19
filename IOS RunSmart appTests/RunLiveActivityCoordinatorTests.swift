import XCTest
@testable import IOS_RunSmart_app

@MainActor
private final class FakeLiveActivityClient: RunLiveActivityClient {
    enum Call: Equatable {
        case request(String)
        case update(String)
        case end(String, RunLiveActivityDismissal)
    }

    var areActivitiesEnabled = true
    var existing: [RunLiveActivityHandle] = []
    var calls: [Call] = []
    var lastState: RunLiveActivityState?
    var failRequests = false
    private var nextID = 0

    func activities() -> [RunLiveActivityHandle] { existing }

    func request(attributes: RunRecordingLiveActivityAttributes, state: RunLiveActivityState, staleDate: Date?) throws -> RunLiveActivityHandle {
        if failRequests { throw NSError(domain: "fake", code: 1) }
        nextID += 1
        let id = "a\(nextID)"
        calls.append(.request(id))
        lastState = state
        return RunLiveActivityHandle(id: id, attributes: attributes, state: state)
    }

    func update(id: String, state: RunLiveActivityState, staleDate: Date?) {
        calls.append(.update(id))
        lastState = state
    }

    func end(id: String, state: RunLiveActivityState, dismissal: RunLiveActivityDismissal) {
        calls.append(.end(id, dismissal))
        lastState = state
    }

    var requestCount: Int { calls.filter { if case .request = $0 { true } else { false } }.count }
    var updateCount: Int { calls.filter { if case .update = $0 { true } else { false } }.count }
}

@MainActor
final class RunLiveActivityCoordinatorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let context = RunLiveActivityCoordinator.RunContext(workoutTitle: "Tempo run", goalDistanceMeters: 8_000, targetPaceSecondsPerKm: 330)

    private func input(
        _ phase: RunRecordingPhase = .recording,
        moving: TimeInterval = 600,
        distance: Double = 2_000,
        accuracy: Double? = 8,
        autoPaused: Bool = false,
        split: KilometerSplit? = nil,
        pending: Date? = nil,
        saved: RunLiveActivityInput.SavedRunSummary? = nil,
        startedAt: Date? = nil
    ) -> RunLiveActivityInput {
        RunLiveActivityInput(
            phase: phase,
            runStartedAt: (phase == .recording || phase == .paused) ? (startedAt ?? start) : nil,
            movingSeconds: moving,
            distanceMeters: distance,
            currentPaceSeconds: 318,
            horizontalAccuracy: accuracy,
            isAutoPaused: autoPaused,
            lastSplit: split,
            pendingRecoveryStartedAt: pending,
            lastSavedRun: saved
        )
    }

    // MARK: Mapping

    func testMapsRecordingWithGoodGPSToRunning() {
        let now = start.addingTimeInterval(700)
        let state = RunLiveActivityMapper.state(from: input(), now: now)
        XCTAssertEqual(state.phase, .running)
        XCTAssertEqual(state.movingSeconds, 600)
        XCTAssertEqual(state.timerStart, now.addingTimeInterval(-600))
        XCTAssertEqual(state.currentPaceSecondsPerKm, 318)
        XCTAssertEqual(state.averagePaceSecondsPerKm, 300)
        XCTAssertNil(state.gpsAccuracyMeters)
    }

    func testMapsWeakOrMissingGPSAfterStartToAcquiring() {
        let weak = RunLiveActivityMapper.state(from: input(accuracy: 90), now: start)
        XCTAssertEqual(weak.phase, .acquiring)
        XCTAssertEqual(weak.gpsAccuracyMeters, 90)
        XCTAssertNil(weak.currentPaceSecondsPerKm)
        XCTAssertEqual(RunLiveActivityMapper.state(from: input(accuracy: nil), now: start).phase, .acquiring)
    }

    func testMapsPausedAndAutoPaused() {
        XCTAssertEqual(RunLiveActivityMapper.state(from: input(.paused), now: start).phase, .paused)
        XCTAssertEqual(RunLiveActivityMapper.state(from: input(.paused, autoPaused: true), now: start).phase, .autoPaused)
        XCTAssertFalse(RunRecordingLiveActivityAttributes.Phase.paused.isClockRunning)
    }

    func testAveragePaceHiddenUnderTwentyMeters() {
        XCTAssertNil(RunLiveActivityMapper.state(from: input(distance: 15), now: start).averagePaceSecondsPerKm)
    }

    func testMapsLastSplit() {
        let state = RunLiveActivityMapper.state(from: input(split: KilometerSplit(km: 3, paceSecondsPerKm: 317.6)), now: start)
        XCTAssertEqual(state.lastSplitKilometer, 3)
        XCTAssertEqual(state.lastSplitPaceSecondsPerKm, 318)
    }

    func testGoalDistanceParsing() {
        XCTAssertEqual(RunLiveActivityMapper.goalDistanceMeters(from: "8 km"), 8_000)
        XCTAssertEqual(RunLiveActivityMapper.goalDistanceMeters(from: "6.5km"), 6_500)
        XCTAssertEqual(RunLiveActivityMapper.goalDistanceMeters(from: "5 mi")!, 8_046.72, accuracy: 0.01)
        XCTAssertNil(RunLiveActivityMapper.goalDistanceMeters(from: "45 min"))
        XCTAssertNil(RunLiveActivityMapper.goalDistanceMeters(from: "30 minutes"))
        XCTAssertEqual(RunLiveActivityMapper.goalDistanceMeters(from: "10K"), 10_000)
        XCTAssertEqual(RunLiveActivityMapper.goalDistanceMeters(from: "800 m"), 800)
        XCTAssertNil(RunLiveActivityMapper.goalDistanceMeters(from: "--"))
        XCTAssertNil(RunLiveActivityMapper.goalDistanceMeters(from: nil))
    }

    // MARK: Policy

    func testPolicyThrottlesSoftChangesAndPassesHardOnes() {
        let base = RunLiveActivityMapper.state(from: input(), now: start)
        var moved = base
        moved.distanceMeters += 40
        XCTAssertFalse(RunLiveActivityUpdatePolicy.shouldSend(last: base, lastSentAt: start, next: moved, now: start.addingTimeInterval(5)))
        XCTAssertTrue(RunLiveActivityUpdatePolicy.shouldSend(last: base, lastSentAt: start, next: moved, now: start.addingTimeInterval(15)))

        var paused = base
        paused.phase = .paused
        XCTAssertTrue(RunLiveActivityUpdatePolicy.shouldSend(last: base, lastSentAt: start, next: paused, now: start.addingTimeInterval(1)))

        var acquiring = base
        acquiring.phase = .acquiring
        XCTAssertFalse(RunLiveActivityUpdatePolicy.shouldSend(last: base, lastSentAt: start, next: acquiring, now: start.addingTimeInterval(1)))

        var split = base
        split.lastSplitKilometer = 1
        XCTAssertTrue(RunLiveActivityUpdatePolicy.shouldSend(last: base, lastSentAt: start, next: split, now: start.addingTimeInterval(1)))

        XCTAssertFalse(RunLiveActivityUpdatePolicy.shouldSend(last: base, lastSentAt: start, next: base, now: start.addingTimeInterval(30)))
        XCTAssertTrue(RunLiveActivityUpdatePolicy.shouldSend(last: base, lastSentAt: start, next: base, now: start.addingTimeInterval(60)))
    }

    func testOneHourOfSteadyRunningStaysWithinBudget() {
        let client = FakeLiveActivityClient()
        let coordinator = RunLiveActivityCoordinator(client: client)
        // Ticks every second, moving 3.1 m/s: the worst case for distance-driven updates.
        for second in 0..<3_600 {
            let now = start.addingTimeInterval(TimeInterval(second))
            coordinator.update(input: input(moving: TimeInterval(second), distance: Double(second) * 3.1), context: context, now: now)
        }
        XCTAssertEqual(client.requestCount, 1)
        XCTAssertLessThanOrEqual(client.updateCount, 240)
        XCTAssertGreaterThanOrEqual(client.updateCount, 60)
    }

    // MARK: Lifecycle

    func testStartsOnceAndKeepsOneActivityAcrossTabSwitches() {
        let client = FakeLiveActivityClient()
        let coordinator = RunLiveActivityCoordinator(client: client)
        coordinator.update(input: input(.acquiringLocation), context: context, now: start)
        XCTAssertTrue(client.calls.isEmpty, "No activity while GPS is searching before Start")

        coordinator.update(input: input(), context: context, now: start)
        coordinator.update(input: input(.paused), context: context, now: start.addingTimeInterval(2))
        coordinator.update(input: input(), context: context, now: start.addingTimeInterval(4))
        XCTAssertEqual(client.requestCount, 1)
        XCTAssertEqual(client.updateCount, 2)
    }

    func testFinishKeepsSummaryCardForThirtyMinutes() {
        let client = FakeLiveActivityClient()
        let coordinator = RunLiveActivityCoordinator(client: client)
        coordinator.update(input: input(), context: context, now: start)
        let saved = RunLiveActivityInput.SavedRunSummary(startedAt: start, distanceMeters: 8_000, movingSeconds: 2_544)
        let end = start.addingTimeInterval(2_600)
        coordinator.update(input: input(.idle, saved: saved), context: context, now: end)

        XCTAssertEqual(client.calls.last, .end("a1", .after(end.addingTimeInterval(1_800))))
        XCTAssertEqual(client.lastState?.phase, .finished)
        XCTAssertEqual(client.lastState?.distanceMeters, 8_000)
        XCTAssertEqual(client.lastState?.averagePaceSecondsPerKm, 318)
        XCTAssertNil(coordinator.current)
    }

    func testDiscardEndsImmediately() {
        let client = FakeLiveActivityClient()
        let coordinator = RunLiveActivityCoordinator(client: client)
        coordinator.update(input: input(), context: context, now: start)
        coordinator.update(input: input(.idle), context: context, now: start.addingTimeInterval(10))
        XCTAssertEqual(client.calls.last, .end("a1", .immediate))
    }

    func testRelaunchAdoptsRecoveryActivityInsteadOfStartingASecond() {
        let client = FakeLiveActivityClient()
        let leftover = RunLiveActivityHandle(
            id: "old",
            attributes: RunRecordingLiveActivityAttributes(runStartedAt: start, workoutTitle: "Tempo run"),
            state: RunLiveActivityMapper.state(from: input(), now: start)
        )
        client.existing = [leftover]
        let coordinator = RunLiveActivityCoordinator(client: client)
        coordinator.reconcileOnLaunch(pendingRecoveryStartedAt: start)
        XCTAssertTrue(client.calls.isEmpty)

        // Prompt still open: keep it.
        coordinator.update(input: input(.idle, pending: start), context: context, now: start.addingTimeInterval(100))
        XCTAssertTrue(client.calls.isEmpty)

        // Runner taps Resume: the recorder lands in .paused with the same start.
        coordinator.update(input: input(.paused), context: context, now: start.addingTimeInterval(110))
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertEqual(client.calls, [.update("old")])
    }

    func testRelaunchDiscardEndsAdoptedActivity() {
        let client = FakeLiveActivityClient()
        client.existing = [RunLiveActivityHandle(
            id: "old",
            attributes: RunRecordingLiveActivityAttributes(runStartedAt: start, workoutTitle: "Run"),
            state: RunLiveActivityMapper.state(from: input(), now: start)
        )]
        let coordinator = RunLiveActivityCoordinator(client: client)
        coordinator.reconcileOnLaunch(pendingRecoveryStartedAt: start)
        coordinator.update(input: input(.idle), context: context, now: start.addingTimeInterval(100))
        XCTAssertEqual(client.calls, [.end("old", .immediate)])
    }

    func testRelaunchSaveWithoutResumeShowsTheSummaryCard() {
        let client = FakeLiveActivityClient()
        client.existing = [RunLiveActivityHandle(
            id: "old",
            attributes: RunRecordingLiveActivityAttributes(runStartedAt: start, workoutTitle: "Run"),
            state: RunLiveActivityMapper.state(from: input(), now: start)
        )]
        let coordinator = RunLiveActivityCoordinator(client: client)
        coordinator.reconcileOnLaunch(pendingRecoveryStartedAt: start)
        let saved = RunLiveActivityInput.SavedRunSummary(startedAt: start, distanceMeters: 5_000, movingSeconds: 1_500)
        let now = start.addingTimeInterval(3_000)
        coordinator.update(input: input(.ready, saved: saved), context: context, now: now)
        XCTAssertEqual(client.calls, [.end("old", .after(now.addingTimeInterval(1_800)))])
        XCTAssertEqual(client.lastState?.phase, .finished)
    }

    func testStartingANewRunEndsTheRecoveredActivityAtOnce() {
        let client = FakeLiveActivityClient()
        client.existing = [RunLiveActivityHandle(
            id: "old",
            attributes: RunRecordingLiveActivityAttributes(runStartedAt: start, workoutTitle: "Run"),
            state: RunLiveActivityMapper.state(from: input(), now: start)
        )]
        let coordinator = RunLiveActivityCoordinator(client: client)
        coordinator.reconcileOnLaunch(pendingRecoveryStartedAt: start)
        let saved = RunLiveActivityInput.SavedRunSummary(startedAt: start, distanceMeters: 5_000, movingSeconds: 1_500)
        coordinator.update(input: input(.acquiringLocation, saved: saved), context: context, now: start.addingTimeInterval(3_000))
        XCTAssertEqual(client.calls, [.end("old", .immediate)])
    }

    func testLaunchEndsOrphansAndOldSchema() {
        let client = FakeLiveActivityClient()
        let state = RunLiveActivityMapper.state(from: input(), now: start)
        client.existing = [
            RunLiveActivityHandle(id: "orphan", attributes: RunRecordingLiveActivityAttributes(runStartedAt: start, workoutTitle: "Run"), state: state),
            RunLiveActivityHandle(id: "legacy", attributes: RunRecordingLiveActivityAttributes(schemaVersion: 1, runStartedAt: start, workoutTitle: "Run"), state: state)
        ]
        let coordinator = RunLiveActivityCoordinator(client: client)
        coordinator.reconcileOnLaunch(pendingRecoveryStartedAt: nil)
        XCTAssertEqual(client.calls, [.end("orphan", .immediate), .end("legacy", .immediate)])
        XCTAssertNil(coordinator.current)
    }

    func testNewRunReplacesActivityFromAnotherRun() {
        let client = FakeLiveActivityClient()
        let coordinator = RunLiveActivityCoordinator(client: client)
        coordinator.update(input: input(), context: context, now: start)
        coordinator.update(input: input(startedAt: start.addingTimeInterval(5_000)), context: context, now: start.addingTimeInterval(5_000))
        XCTAssertEqual(client.calls, [.request("a1"), .end("a1", .immediate), .request("a2")])
    }

    func testDisabledActivitiesEndAndNeverStart() {
        let client = FakeLiveActivityClient()
        let coordinator = RunLiveActivityCoordinator(client: client)
        coordinator.update(input: input(), context: context, now: start)
        client.areActivitiesEnabled = false
        coordinator.update(input: input(), context: context, now: start.addingTimeInterval(1))
        coordinator.update(input: input(), context: context, now: start.addingTimeInterval(2))
        XCTAssertEqual(client.calls, [.request("a1"), .end("a1", .immediate)])
    }

    func testFailedRequestRetriesAfterAMinuteNotEveryTick() {
        let client = FakeLiveActivityClient()
        client.failRequests = true
        let coordinator = RunLiveActivityCoordinator(client: client)
        for second in 0..<59 {
            coordinator.update(input: input(), context: context, now: start.addingTimeInterval(TimeInterval(second)))
        }
        client.failRequests = false
        coordinator.update(input: input(), context: context, now: start.addingTimeInterval(59))
        XCTAssertEqual(client.requestCount, 0)
        coordinator.update(input: input(), context: context, now: start.addingTimeInterval(60))
        XCTAssertEqual(client.requestCount, 1)
    }

    // MARK: Schema

    func testDecodesSchemaOneStateAndAttributes() throws {
        let legacyState = #"{"distanceLabel":"4.20","movingTimeLabel":"21:00","paceLabel":"5:00","isPaused":true}"#
        let state = try JSONDecoder().decode(RunLiveActivityState.self, from: Data(legacyState.utf8))
        XCTAssertEqual(state.phase, .paused)

        let legacyAttributes = #"{"workoutTitle":"Easy run"}"#
        let attributes = try JSONDecoder().decode(RunRecordingLiveActivityAttributes.self, from: Data(legacyAttributes.utf8))
        XCTAssertEqual(attributes.schemaVersion, 1)
        XCTAssertEqual(attributes.workoutTitle, "Easy run")
    }

    func testStateRoundTripsUnderFourKilobytes() throws {
        let state = RunLiveActivityMapper.state(from: input(split: KilometerSplit(km: 12, paceSecondsPerKm: 300)), now: start)
        let attributes = RunRecordingLiveActivityAttributes(runStartedAt: start, workoutTitle: String(repeating: "x", count: 80), goalDistanceMeters: 42_195, targetPaceSecondsPerKm: 330)
        let stateData = try JSONEncoder().encode(state)
        let attributesData = try JSONEncoder().encode(attributes)
        XCTAssertEqual(try JSONDecoder().decode(RunLiveActivityState.self, from: stateData), state)
        XCTAssertLessThan(stateData.count + attributesData.count, 4_096)
    }
}
