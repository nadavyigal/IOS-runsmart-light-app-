import Foundation
import Observation
import WorkoutKit
import HealthKit

/// Uses the same measurable stages as the phone guide; incomplete instructions are never guessed.
enum AppleWorkoutFactory {
    static func makePlan(for workout: WorkoutSummary) throws -> WorkoutPlan {
        guard !workout.isComplete, workout.kind != .strength, workout.kind != .recovery,
              let guide = StructuredWorkoutFactory.makeGuideSteps(for: workout), !guide.isEmpty else {
            throw AppleWorkoutError.incompleteWorkout
        }
        var stages = guide
        let warmup = stages.first?.kind == .warmup ? try step(stages.removeFirst()) : nil
        let cooldown = stages.last?.kind == .cooldown ? try step(stages.removeLast()) : nil
        let intervals = try stages.map { stage in
            IntervalStep(stage.kind == .recovery ? .recovery : .work, step: try step(stage))
        }
        guard !intervals.isEmpty else { throw AppleWorkoutError.incompleteWorkout }
        let custom = CustomWorkout(activity: .running, location: .outdoor, displayName: workout.title,
                                   warmup: warmup, blocks: [IntervalBlock(steps: intervals)], cooldown: cooldown)
        return WorkoutPlan(.custom(custom), id: workout.id)
    }

    private static func step(_ stage: GuideStep) throws -> WorkoutKit.WorkoutStep {
        let goal: WorkoutGoal
        switch stage.target {
        case .duration(let seconds):
            guard seconds.isFinite, seconds > 0 else { throw AppleWorkoutError.incompleteWorkout }
            goal = .time(seconds, .seconds)
        case .distance(let meters):
            guard meters.isFinite, meters > 0 else { throw AppleWorkoutError.incompleteWorkout }
            goal = .distance(meters, .meters)
        }
        guard CustomWorkout.supportsGoal(goal, activity: .running, location: .outdoor) else {
            throw AppleWorkoutError.incompleteWorkout
        }
        var result = WorkoutKit.WorkoutStep(goal: goal)
        if let pace = stage.paceBand {
            guard pace.fast.isFinite, pace.slow.isFinite, pace.fast > 0, pace.slow >= pace.fast else {
                throw AppleWorkoutError.incompleteWorkout
            }
            let alert = SpeedRangeAlert.speed((1000 / pace.slow)...(1000 / pace.fast), unit: .metersPerSecond)
            guard CustomWorkout.supportsAlert(alert, activity: .running, location: .outdoor) else {
                throw AppleWorkoutError.incompleteWorkout
            }
            result.alert = alert
        }
        return result
    }
}

enum AppleWorkoutError: LocalizedError {
    case unavailable, denied, full, incompleteWorkout, pastDate, busy, notConfirmed
    var errorDescription: String? {
        switch self {
        case .unavailable: "Workout scheduling requires a supported iPhone and paired Apple Watch."
        case .denied: "Allow RunSmart to add workouts in Settings, then try again."
        case .full: "Apple Workout has reached its scheduled workout limit. Remove a workout and try again."
        case .incompleteWorkout: "This session needs complete running steps before it can be sent to Apple Watch."
        case .pastDate: "Reschedule this session for today or later before sending it."
        case .busy: "A workout update is in progress. Please try again."
        case .notConfirmed: "Apple Workout has not confirmed this update. Please try again."
        }
    }
}

@MainActor
protocol AppleWorkoutScheduling {
    var isSupported: Bool { get }
    var limit: Int { get }
    func authorize() async -> Bool
    func isAuthorized() async -> Bool
    func scheduled() async -> [ScheduledWorkoutPlan]
    func schedule(_ plan: WorkoutPlan, at date: DateComponents) async
    func remove(_ plan: WorkoutPlan, at date: DateComponents) async
}

@MainActor
struct SystemAppleWorkoutScheduler: AppleWorkoutScheduling {
    var isSupported: Bool { WorkoutScheduler.isSupported }
    var limit: Int { WorkoutScheduler.maxAllowedScheduledWorkoutCount }
    func authorize() async -> Bool { await WorkoutScheduler.shared.requestAuthorization() == .authorized }
    func isAuthorized() async -> Bool { await WorkoutScheduler.shared.authorizationState == .authorized }
    func scheduled() async -> [ScheduledWorkoutPlan] { await WorkoutScheduler.shared.scheduledWorkouts }
    func schedule(_ plan: WorkoutPlan, at date: DateComponents) async { await WorkoutScheduler.shared.schedule(plan, at: date) }
    func remove(_ plan: WorkoutPlan, at date: DateComponents) async { await WorkoutScheduler.shared.remove(plan, at: date) }
}

@Observable
@MainActor
final class AppleWorkoutService {
    static let shared = AppleWorkoutService()
    private let scheduler: any AppleWorkoutScheduling
    private var updating = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var lastIssue: String?

    private func acquire() async {
        if updating { await withCheckedContinuation { waiters.append($0) } }
        else { updating = true }
    }

    private func release() {
        if waiters.isEmpty { updating = false }
        else { waiters.removeFirst().resume() }
    }
    nonisolated deinit {}

    init(scheduler: (any AppleWorkoutScheduling)? = nil) { self.scheduler = scheduler ?? SystemAppleWorkoutScheduler() }

    /// ScheduledWorkoutPlan expands a day into full Gregorian components (including calendar,
    /// timezone and midnight). Compare the day fields we scheduled, not the entire value.
    private static func sameDay(_ a: DateComponents, _ b: DateComponents) -> Bool {
        a.year == b.year && a.month == b.month && a.day == b.day
    }

    private static func scheduleDate(for date: Date, timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.calendar = calendar
        components.timeZone = timeZone
        return components
    }

    func send(_ workout: WorkoutSummary, now: Date = Date(), calendar: Calendar = .current) async throws {
        await acquire()
        defer { release() }
        lastIssue = nil
        guard scheduler.isSupported else { throw AppleWorkoutError.unavailable }
        let plan = try AppleWorkoutFactory.makePlan(for: workout)
        guard calendar.startOfDay(for: workout.scheduledDate) >= calendar.startOfDay(for: now) else { throw AppleWorkoutError.pastDate }
        guard await scheduler.authorize() else { throw AppleWorkoutError.denied }
        let scheduled = await scheduler.scheduled()
        let previous = scheduled.filter { $0.plan.id == plan.id }
        guard scheduled.count - previous.count < scheduler.limit else { throw AppleWorkoutError.full }
        let date = Self.scheduleDate(for: workout.scheduledDate, timeZone: calendar.timeZone)
        // Replace the same logical item, including moves, rather than adding another UUID.
        for old in previous { await scheduler.remove(old.plan, at: old.date) }
        await scheduler.schedule(plan, at: date)
        let confirmed = await scheduler.scheduled().filter { $0.plan.id == plan.id }
        guard confirmed.count == 1, confirmed.first?.plan == plan, confirmed.first.map({ Self.sameDay($0.date, date) }) == true else {
            throw AppleWorkoutError.notConfirmed
        }
    }

    /// Only call with a successful, full active-plan fetch. A failed read is not a cancellation.
    /// Existing exports follow edits; new items still require the runner's explicit Send action.
    func reconcile(workouts: [WorkoutSummary], now: Date = Date(), calendar: Calendar = .current) async {
        await acquire()
        defer { release() }
        guard scheduler.isSupported else { return }
        guard await scheduler.isAuthorized() else { return } // Never prompt during plan refresh.
        for old in await scheduler.scheduled() {
            guard let current = workouts.first(where: { $0.id == old.plan.id }),
                  !current.isComplete,
                  calendar.startOfDay(for: current.scheduledDate) >= calendar.startOfDay(for: now),
                  let plan = try? AppleWorkoutFactory.makePlan(for: current) else {
                await scheduler.remove(old.plan, at: old.date)
                if await scheduler.scheduled().contains(where: { $0.plan.id == old.plan.id && Self.sameDay($0.date, old.date) }) {
                    lastIssue = "An Apple Watch workout could not be removed. Remove it in Apple's Workout app before starting it."
                }
                continue
            }
            let date = Self.scheduleDate(for: current.scheduledDate, timeZone: calendar.timeZone)
            if old.plan != plan || !Self.sameDay(old.date, date) {
                await scheduler.remove(old.plan, at: old.date)
                await scheduler.schedule(plan, at: date)
                let confirmed = await scheduler.scheduled().filter { $0.plan.id == plan.id }
                if confirmed.count != 1 || confirmed.first?.plan != plan || confirmed.first.map({ Self.sameDay($0.date, date) }) != true {
                    lastIssue = "An Apple Watch workout update was not confirmed. Open the session and use Send to Apple Watch again."
                }
            }
        }
    }
}
