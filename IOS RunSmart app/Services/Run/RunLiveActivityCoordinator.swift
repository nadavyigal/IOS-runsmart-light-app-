import ActivityKit
import Combine
import Foundation

typealias RunLiveActivityState = RunRecordingLiveActivityAttributes.ContentState

/// Everything the Live Activity needs from the recorder, read at one moment.
struct RunLiveActivityInput: Equatable {
    var phase: RunRecordingPhase
    var runStartedAt: Date?
    var movingSeconds: TimeInterval
    var distanceMeters: Double
    var currentPaceSeconds: TimeInterval?
    var horizontalAccuracy: Double?
    var isAutoPaused: Bool
    var lastSplit: KilometerSplit?
    var pendingRecoveryStartedAt: Date?
    var lastSavedRun: SavedRunSummary?

    struct SavedRunSummary: Equatable {
        var startedAt: Date
        var distanceMeters: Double
        var movingSeconds: TimeInterval
    }

    var isLive: Bool { phase == .recording || phase == .paused }

    /// GPS counts as weak after Start when there is no fix yet or the last one is worse than
    /// the recorder's own acceptance threshold.
    var hasWeakGPS: Bool {
        guard let horizontalAccuracy, horizontalAccuracy >= 0 else { return true }
        return horizontalAccuracy > RunRecorder.acceptedRecordingAccuracy
    }
}

/// Pure mapping from recorder input to Live Activity state.
enum RunLiveActivityMapper {
    static func state(from input: RunLiveActivityInput, now: Date) -> RunLiveActivityState {
        let phase: RunRecordingLiveActivityAttributes.Phase
        if input.phase == .paused {
            phase = input.isAutoPaused ? .autoPaused : .paused
        } else {
            phase = input.hasWeakGPS ? .acquiring : .running
        }
        let moving = max(0, Int(input.movingSeconds.rounded()))
        return RunLiveActivityState(
            phase: phase,
            timerStart: now.addingTimeInterval(-TimeInterval(moving)),
            movingSeconds: moving,
            distanceMeters: input.distanceMeters,
            currentPaceSecondsPerKm: phase == .running ? wholeSeconds(input.currentPaceSeconds) : nil,
            averagePaceSecondsPerKm: averagePace(distanceMeters: input.distanceMeters, movingSeconds: input.movingSeconds),
            lastSplitKilometer: input.lastSplit?.km,
            lastSplitPaceSecondsPerKm: wholeSeconds(input.lastSplit?.paceSecondsPerKm),
            gpsAccuracyMeters: phase == .acquiring ? input.horizontalAccuracy.flatMap { $0 >= 0 ? Int($0.rounded()) : nil } : nil
        )
    }

    static func finishedState(for run: RunLiveActivityInput.SavedRunSummary, lastSplit: (km: Int?, pace: Int?), now: Date) -> RunLiveActivityState {
        let moving = max(0, Int(run.movingSeconds.rounded()))
        return RunLiveActivityState(
            phase: .finished,
            timerStart: now.addingTimeInterval(-TimeInterval(moving)),
            movingSeconds: moving,
            distanceMeters: run.distanceMeters,
            averagePaceSecondsPerKm: averagePace(distanceMeters: run.distanceMeters, movingSeconds: run.movingSeconds),
            lastSplitKilometer: lastSplit.km,
            lastSplitPaceSecondsPerKm: lastSplit.pace
        )
    }

    /// Average pace, hidden under 20 m like the recorder's own label.
    static func averagePace(distanceMeters: Double, movingSeconds: TimeInterval) -> Int? {
        guard distanceMeters >= 20, movingSeconds > 0 else { return nil }
        return wholeSeconds(movingSeconds / (distanceMeters / 1_000))
    }

    private static func wholeSeconds(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return Int(value.rounded())
    }

    /// Planned distance in meters from a plan label such as "8 km", "6.5km" or "5 mi".
    static func goalDistanceMeters(from label: String?) -> Double? {
        guard let label = label?.lowercased(), !label.isEmpty else { return nil }
        let number = label.prefix { "0123456789.,".contains($0) }.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(number), value > 0 else { return nil }
        let unit = label.dropFirst(number.count).trimmingCharacters(in: .whitespaces)
        // Only distance units count; "45 min" is a duration, not 45 miles.
        let word = unit.prefix { $0.isLetter }
        switch word {
        case "mi", "mile", "miles": return value * 1_609.344
        case "km", "k", "": return value * 1_000
        case "m": return value
        default: return nil
        }
    }
}

/// Decides when an update is worth sending, so a run stays near 60-240 updates an hour.
/// The clock is drawn by the timer view, so time passing alone never needs an update.
enum RunLiveActivityUpdatePolicy {
    static let minimumInterval: TimeInterval = 15
    static let heartbeatInterval: TimeInterval = 60
    static let staleAfter: TimeInterval = 120
    static let minimumDistanceChange: Double = 10
    static let finishedCardLifetime: TimeInterval = 30 * 60

    static func shouldSend(last: RunLiveActivityState?, lastSentAt: Date?, next: RunLiveActivityState, now: Date) -> Bool {
        guard let last, let lastSentAt else { return true }
        if isHardChange(from: last.phase, to: next.phase) { return true }
        if last.lastSplitKilometer != next.lastSplitKilometer { return true }
        let elapsed = now.timeIntervalSince(lastSentAt)
        if elapsed >= heartbeatInterval { return true }
        guard elapsed >= minimumInterval else { return false }
        return last.phase != next.phase
            || abs(next.distanceMeters - last.distanceMeters) >= minimumDistanceChange
            || last.currentPaceSecondsPerKm != next.currentPaceSecondsPerKm
    }

    /// Pause, resume and finish show at once. GPS flapping between running and acquiring
    /// waits for the normal interval.
    static func isHardChange(from old: RunRecordingLiveActivityAttributes.Phase, to new: RunRecordingLiveActivityAttributes.Phase) -> Bool {
        guard old != new else { return false }
        let soft: Set<RunRecordingLiveActivityAttributes.Phase> = [.running, .acquiring]
        return !(soft.contains(old) && soft.contains(new))
    }
}

enum RunLiveActivityDismissal: Equatable {
    case immediate
    case after(Date)
}

struct RunLiveActivityHandle: Equatable {
    var id: String
    var attributes: RunRecordingLiveActivityAttributes
    var state: RunLiveActivityState

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.state == rhs.state }
}

/// The ActivityKit calls the coordinator makes; a fake stands in for it in tests.
@MainActor
protocol RunLiveActivityClient: AnyObject {
    var areActivitiesEnabled: Bool { get }
    func activities() -> [RunLiveActivityHandle]
    func request(attributes: RunRecordingLiveActivityAttributes, state: RunLiveActivityState, staleDate: Date?) throws -> RunLiveActivityHandle
    func update(id: String, state: RunLiveActivityState, staleDate: Date?)
    func end(id: String, state: RunLiveActivityState, dismissal: RunLiveActivityDismissal)
}

/// Owns the run Live Activity for the whole app (not one tab): starts it when a run is live,
/// throttles updates, adopts or ends activities left by a killed process, and ends it on
/// finish (summary card for 30 minutes) or discard (removed at once).
@MainActor
final class RunLiveActivityCoordinator: ObservableObject {
    struct RunContext: Equatable {
        var workoutTitle: String
        var goalDistanceMeters: Double?
        var targetPaceSecondsPerKm: Int?
    }

    private let client: RunLiveActivityClient
    var isEnabled: () -> Bool = { true }
    private(set) var current: RunLiveActivityHandle?
    private var lastSentAt: Date?
    private var sawLiveRun = false
    private var lastRequestFailureAt: Date?
    private var cancellables = Set<AnyCancellable>()
    private var isBound = false

    static let requestRetryInterval: TimeInterval = 60
    static let sameRunTolerance: TimeInterval = 1

    init(client: RunLiveActivityClient? = nil) {
        self.client = client ?? ActivityKitRunLiveActivityClient()
    }

    // MARK: Launch

    /// Ends activities a killed or older build left behind, except the one that belongs to an
    /// unanswered recovery prompt, which is adopted so resuming never starts a second one.
    func reconcileOnLaunch(pendingRecoveryStartedAt: Date?) {
        for handle in client.activities() {
            let isCurrentSchema = handle.attributes.schemaVersion == RunRecordingLiveActivityAttributes.currentSchemaVersion
            if isCurrentSchema, current == nil, let pending = pendingRecoveryStartedAt,
               Self.isSameRun(handle.attributes.runStartedAt, pending) {
                current = handle
                lastSentAt = nil
                sawLiveRun = false
            } else {
                client.end(id: handle.id, state: handle.state, dismissal: .immediate)
            }
        }
    }

    // MARK: Updates

    func update(input: RunLiveActivityInput, context: @autoclosure () -> RunContext, now: Date = Date()) {
        guard client.areActivitiesEnabled, isEnabled() else {
            endCurrent(dismissal: .immediate, state: current?.state)
            return
        }

        guard input.isLive, let startedAt = input.runStartedAt else {
            handleNotLive(input: input, now: now)
            return
        }

        if let current, !Self.isSameRun(current.attributes.runStartedAt, startedAt) {
            endCurrent(dismissal: .immediate, state: current.state)
        }

        var state = RunLiveActivityMapper.state(from: input, now: now)
        state.splitHighlightUntil = splitHighlight(for: state, now: now)
        let staleDate = now.addingTimeInterval(RunLiveActivityUpdatePolicy.staleAfter)

        guard var handle = current else {
            if let failedAt = lastRequestFailureAt, now.timeIntervalSince(failedAt) < Self.requestRetryInterval { return }
            let ctx = context()
            let attributes = RunRecordingLiveActivityAttributes(
                runStartedAt: startedAt,
                workoutTitle: ctx.workoutTitle,
                goalDistanceMeters: ctx.goalDistanceMeters,
                targetPaceSecondsPerKm: ctx.targetPaceSecondsPerKm
            )
            do {
                current = try client.request(attributes: attributes, state: state, staleDate: staleDate)
                lastSentAt = now
                sawLiveRun = true
                lastRequestFailureAt = nil
            } catch {
                lastRequestFailureAt = now
#if DEBUG
                print("RunLiveActivityCoordinator: request failed: \(error)")
#endif
            }
            return
        }

        sawLiveRun = true
        let lastState: RunLiveActivityState? = lastSentAt == nil ? nil : handle.state
        guard RunLiveActivityUpdatePolicy.shouldSend(last: lastState, lastSentAt: lastSentAt, next: state, now: now) else { return }
        client.update(id: handle.id, state: state, staleDate: staleDate)
        handle.state = state
        current = handle
        lastSentAt = now
    }

    /// A newly crossed kilometer pops the split chip for 30 seconds; it then hides on the next
    /// update. A recovered run's existing splits never pop.
    static let splitHighlightDuration: TimeInterval = 30

    private func splitHighlight(for state: RunLiveActivityState, now: Date) -> Date? {
        guard let previous = current?.state, lastSentAt != nil else { return nil }
        if let km = state.lastSplitKilometer, km != previous.lastSplitKilometer {
            return now.addingTimeInterval(Self.splitHighlightDuration)
        }
        guard let until = previous.splitHighlightUntil, until > now else { return nil }
        return until
    }

    private func handleNotLive(input: RunLiveActivityInput, now: Date) {
        guard let current else { return }
        // Waiting for the runner to answer the recovery prompt: keep the adopted activity.
        if let pending = input.pendingRecoveryStartedAt, Self.isSameRun(current.attributes.runStartedAt, pending) {
            return
        }
        // A saved run gets the summary card: a normal finish, or Save on the recovery prompt.
        // Not when a new run's Start saved the old recovered run on the way (its card would
        // sit beside the new run's activity).
        let isStartingNewRun = !sawLiveRun && input.phase == .acquiringLocation
        if !isStartingNewRun, let saved = input.lastSavedRun, Self.isSameRun(saved.startedAt, current.attributes.runStartedAt) {
            let finished = RunLiveActivityMapper.finishedState(
                for: saved,
                lastSplit: (current.state.lastSplitKilometer, current.state.lastSplitPaceSecondsPerKm),
                now: now
            )
            endCurrent(dismissal: .after(now.addingTimeInterval(RunLiveActivityUpdatePolicy.finishedCardLifetime)), state: finished)
        } else {
            endCurrent(dismissal: .immediate, state: current.state)
        }
    }

    private func endCurrent(dismissal: RunLiveActivityDismissal, state: RunLiveActivityState?) {
        guard let current else { return }
        client.end(id: current.id, state: state ?? current.state, dismissal: dismissal)
        self.current = nil
        lastSentAt = nil
        sawLiveRun = false
    }

    static func isSameRun(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < sameRunTolerance
    }

    // MARK: App wiring

    /// Binds to the app's single recorder and router once. Recorder changes drive updates
    /// whatever tab is on screen, and button taps go straight to the recorder.
    func bind(recorder: RunRecorder, router: AppRouter) {
        guard !isBound else { return }
        isBound = true

        reconcileOnLaunch(pendingRecoveryStartedAt: recorder.pendingRecovery?.startedAt)

        RunLiveActivityActionRouter.shared.handler = { [weak recorder, weak router] action in
            guard let recorder else { return }
            switch action {
            case .pauseResume:
                switch recorder.phase {
                case .recording:
                    RunSmartHaptics.light()
                    recorder.pause()
                case .paused:
                    RunSmartHaptics.light()
                    recorder.resume()
                default:
                    break
                }
            case .finish:
                guard recorder.phase == .recording || recorder.phase == .paused else { return }
                router?.selectedTab = .run
                router?.liveActivityFinishRequested = true
            }
        }

        recorder.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self, weak recorder, weak router] _ in
                MainActor.assumeIsolated {
                    guard let self, let recorder else { return }
                    self.update(input: Self.input(from: recorder), context: Self.context(recorder: recorder, router: router))
                }
            }
            .store(in: &cancellables)

        update(input: Self.input(from: recorder), context: Self.context(recorder: recorder, router: router))
    }

    static func input(from recorder: RunRecorder) -> RunLiveActivityInput {
        RunLiveActivityInput(
            phase: recorder.phase,
            runStartedAt: recorder.currentRunStartedAt,
            movingSeconds: recorder.movingSeconds,
            distanceMeters: recorder.distanceMeters,
            currentPaceSeconds: recorder.currentPaceSeconds,
            horizontalAccuracy: recorder.horizontalAccuracy,
            isAutoPaused: recorder.isAutoPaused,
            lastSplit: recorder.completedKilometerSplits.last,
            pendingRecoveryStartedAt: recorder.pendingRecovery?.startedAt,
            lastSavedRun: recorder.lastSavedRun.map {
                .init(startedAt: $0.startedAt, distanceMeters: $0.distanceMeters, movingSeconds: $0.movingTimeSeconds)
            }
        )
    }

    static func context(recorder: RunRecorder, router: AppRouter?) -> RunContext {
        let planned = router?.plannedWorkout
        return RunContext(
            workoutTitle: planned?.title ?? recorder.activeWorkoutTitle ?? "Free Run",
            goalDistanceMeters: RunLiveActivityMapper.goalDistanceMeters(from: planned?.distance),
            targetPaceSecondsPerKm: planned?.targetPaceSecondsPerKm
        )
    }
}

/// The real ActivityKit calls.
@MainActor
final class ActivityKitRunLiveActivityClient: RunLiveActivityClient {
    private typealias RunActivity = Activity<RunRecordingLiveActivityAttributes>

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func activities() -> [RunLiveActivityHandle] {
        RunActivity.activities.map { RunLiveActivityHandle(id: $0.id, attributes: $0.attributes, state: $0.content.state) }
    }

    func request(attributes: RunRecordingLiveActivityAttributes, state: RunLiveActivityState, staleDate: Date?) throws -> RunLiveActivityHandle {
        let activity = try RunActivity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: staleDate),
            pushType: nil
        )
        return RunLiveActivityHandle(id: activity.id, attributes: attributes, state: state)
    }

    func update(id: String, state: RunLiveActivityState, staleDate: Date?) {
        guard let activity = RunActivity.activities.first(where: { $0.id == id }) else { return }
        Task { await activity.update(ActivityContent(state: state, staleDate: staleDate)) }
    }

    func end(id: String, state: RunLiveActivityState, dismissal: RunLiveActivityDismissal) {
        guard let activity = RunActivity.activities.first(where: { $0.id == id }) else { return }
        let policy: ActivityUIDismissalPolicy
        switch dismissal {
        case .immediate: policy = .immediate
        case .after(let date): policy = .after(date)
        }
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: policy) }
    }
}
