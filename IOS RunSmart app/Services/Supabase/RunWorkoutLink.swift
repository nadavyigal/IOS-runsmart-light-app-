import Foundation

/// Natural key of a `runs` row: the same pair the upsert conflicts on.
struct RunSourceKey: Codable, Hashable {
    let sourceProvider: String
    let sourceActivityID: String

    var dataSource: RunSmartDataSource? {
        switch sourceProvider {
        case "runsmart_ios": return .runSmart
        case "garmin": return .garmin
        case "healthkit": return .healthKit
        default: return nil
        }
    }
}

extension RecordedRun {
    var supabaseSourceProvider: String {
        switch source {
        case .runSmart: return "runsmart_ios"
        case .garmin: return "garmin"
        case .healthKit: return "healthkit"
        }
    }

    /// Mirrors `DBRunInsert`, so the key finds the row that run was upserted as.
    var runSourceKey: RunSourceKey {
        RunSourceKey(sourceProvider: supabaseSourceProvider, sourceActivityID: providerActivityID ?? id.uuidString)
    }
}

enum RunWorkoutLinkResult: String, Decodable {
    case completed
    case alreadyCompleted = "already_completed"
    case runNotSynced = "run_not_synced"
    case notAvailable = "not_available"

    var didComplete: Bool { self == .completed || self == .alreadyCompleted }
}

struct PendingRunLink: Codable, Equatable {
    let id: UUID
    let authUserID: UUID
    let key: RunSourceKey
    let workoutID: UUID
    let payload: DBWorkoutCompletionUpdate
    let queuedAt: Date
    var attemptCount: Int
}

struct CompleteRunWorkoutParams: Encodable {
    let record: PendingRunLink

    private enum CodingKeys: String, CodingKey {
        case athlete = "p_expected_athlete"
        case workout = "p_workout_id"
        case provider = "p_source_provider"
        case activity = "p_source_activity_id"
        case completedAt = "p_completed_at"
        case distance = "p_actual_distance_km"
        case duration = "p_actual_duration_minutes"
        case pace = "p_actual_pace"
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(record.authUserID, forKey: .athlete)
        try values.encode(record.workoutID, forKey: .workout)
        try values.encode(record.key.sourceProvider, forKey: .provider)
        try values.encode(record.key.sourceActivityID, forKey: .activity)
        try values.encode(record.payload.completedAt, forKey: .completedAt)
        try values.encode(record.payload.actualDistanceKm, forKey: .distance)
        try values.encode(record.payload.actualDurationMinutes, forKey: .duration)
        try values.encode(record.payload.actualPace, forKey: .pace)
    }
}

/// One durable retry record for the link and its actuals. Legacy split records
/// cannot prove the source of their actuals. The upgrade pass uses persisted links.
final class RunWorkoutLinkOutbox {
    static let shared = RunWorkoutLinkOutbox()
    static let maxAttempts = 5
    static let maxAge: TimeInterval = 14 * 24 * 3600

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private let retryGate = RunWorkoutPassGate()
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, key: String = "runsmart.runs.pendingWorkoutCompletions.v2", now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.key = key
        self.now = now
    }

    func pending() -> [PendingRunLink] {
        lock.lock()
        defer { lock.unlock() }
        return load()
    }

    /// Preserve the first pending match for this run until the database accepts or rejects it.
    @discardableResult
    func enqueue(authUserID: UUID, key runKey: RunSourceKey, workoutID: UUID, payload: DBWorkoutCompletionUpdate) -> PendingRunLink {
        lock.lock()
        defer { lock.unlock() }
        var list = load()
        if let existing = list.first(where: { $0.authUserID == authUserID && $0.key == runKey }) {
            return existing
        }
        let record = PendingRunLink(id: UUID(), authUserID: authUserID, key: runKey, workoutID: workoutID, payload: payload, queuedAt: now(), attemptCount: 0)
        list.append(record)
        save(list)
        return record
    }

    func remove(_ record: PendingRunLink) {
        lock.lock()
        defer { lock.unlock() }
        save(load().filter { $0.id != record.id })
    }

    func recordFailure(_ record: PendingRunLink) {
        lock.lock()
        defer { lock.unlock() }
        var list = load()
        guard let index = list.firstIndex(where: { $0.id == record.id }) else { return }
        list[index].attemptCount += 1
        if list[index].attemptCount >= Self.maxAttempts {
            print("[TrainingPlanRepo] giving up on run completion after \(Self.maxAttempts) attempts workout=\(record.workoutID)")
            list.remove(at: index)
        }
        save(list)
    }

    func attempt(_ record: PendingRunLink, send: (PendingRunLink) async throws -> RunWorkoutLinkResult) async -> RunWorkoutLinkResult? {
        if now().timeIntervalSince(record.queuedAt) > Self.maxAge {
            remove(record)
            return nil
        }
        do {
            let result = try await send(record)
            if result != .runNotSynced { remove(record) }
            return result
        } catch is CancellationError {
            return nil
        } catch {
            print("[TrainingPlanRepo] run completion write failed:", error)
            recordFailure(record)
            return nil
        }
    }

    /// A run that has yet to upload waits without consuming an attempt. If we
    /// can restore its exact local copy, try the same atomic write once more.
    func retryPending(
        authUserID: UUID,
        isHidden: (RunSourceKey) -> Bool = { _ in false },
        restoreRun: (RunSourceKey) async -> Bool = { _ in false },
        send: (PendingRunLink) async throws -> RunWorkoutLinkResult
    ) async -> [UUID] {
        guard await retryGate.tryEnter() else { return [] }
        var completed: [UUID] = []
        for record in pending() where record.authUserID == authUserID {
            if isHidden(record.key) {
                remove(record)
                continue
            }
            var result = await attempt(record, send: send)
            if result == .runNotSynced, await restoreRun(record.key) {
                if isHidden(record.key) {
                    remove(record)
                    continue
                }
                result = await attempt(record, send: send)
            }
            if result?.didComplete == true { completed.append(record.workoutID) }
        }
        await retryGate.leave()
        return completed
    }

    private func load() -> [PendingRunLink] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode([PendingRunLink].self, from: data) else { return [] }
        return records
    }

    private func save(_ list: [PendingRunLink]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: key)
    }
}

private actor RunWorkoutPassGate {
    private var running = false

    func tryEnter() -> Bool {
        if running { return false }
        running = true
        return true
    }

    func leave() { running = false }
}

struct RunWorkoutBackfillReport: Equatable {
    var candidateRuns: Int
    var matched: Int
    var unmatched: Int
    var applied: Int
    var dryRun: Bool
}

struct RunWorkoutBackfillIncumbent {
    let workoutID: UUID
    // A hidden or unusable activity reserves its target without triggering a write.
    let run: RecordedRun?
}

/// One pass per account and install to finish legacy links and match recent unlinked runs.
enum RunWorkoutBackfill {
    static let lookbackDays = 30
    static let dryRunDefaultsKey = "runsmart.debug.runWorkoutBackfillDryRun"
    private static let gate = RunWorkoutPassGate()

    /// The flag is per account, so a second account on the same install still gets its pass.
    static func flagKey(for userID: UUID) -> String {
        "runsmart.runs.workoutLinkBackfill.v3.\(userID.uuidString)"
    }

    /// Dry-run is a debug switch only: `-runsmart.debug.runWorkoutBackfillDryRun YES` in the scheme.
    static var isDryRunRequested: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: dryRunDefaultsKey)
        #else
        return false
        #endif
    }

    /// Returns nil when the pass was skipped (already done, already running, or data unavailable).
    /// Counts are logged before anything is written. The flag is set only after a real pass, so a
    /// load failure or a dry run retries on the next launch.
    static func runOnce(
        userID: UUID,
        defaults: UserDefaults = .standard,
        dryRun: Bool,
        calendar: Calendar = .current,
        loadRuns: () async -> [RecordedRun]?,
        loadWorkouts: () async -> [WorkoutSummary]?,
        loadLinkedRuns: ([WorkoutSummary]) async -> [RunWorkoutBackfillIncumbent]? = { _ in [] },
        apply: (RecordedRun, WorkoutSummary) async -> Bool
    ) async -> RunWorkoutBackfillReport? {
        guard !defaults.bool(forKey: flagKey(for: userID)) else { return nil }
        guard await gate.tryEnter() else { return nil }
        let report = await perform(
            userID: userID, defaults: defaults, dryRun: dryRun, calendar: calendar,
            loadRuns: loadRuns, loadWorkouts: loadWorkouts, loadLinkedRuns: loadLinkedRuns, apply: apply
        )
        await gate.leave()
        return report
    }

    private static func perform(
        userID: UUID,
        defaults: UserDefaults,
        dryRun: Bool,
        calendar: Calendar,
        loadRuns: () async -> [RecordedRun]?,
        loadWorkouts: () async -> [WorkoutSummary]?,
        loadLinkedRuns: ([WorkoutSummary]) async -> [RunWorkoutBackfillIncumbent]?,
        apply: (RecordedRun, WorkoutSummary) async -> Bool
    ) async -> RunWorkoutBackfillReport? {
        guard let workouts = await loadWorkouts() else { return nil }
        let incomplete = workouts.filter { !$0.isComplete }
        guard let incumbents = await loadLinkedRuns(incomplete), let runs = await loadRuns() else { return nil }
        let workoutByID = Dictionary(incomplete.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let reserved = Set(incumbents.map(\.workoutID))
        let linkedPairs = incumbents.compactMap { incumbent -> (RecordedRun, WorkoutSummary)? in
            guard let run = incumbent.run, let workout = workoutByID[incumbent.workoutID] else { return nil }
            return (run, workout)
        }
        let available = incomplete.filter { !reserved.contains($0.id) }
        let pairs = linkedPairs + TrainingPlanRepository.assignRuns(runs, to: available, calendar: calendar)
        let candidateCount = runs.count + linkedPairs.count
        var report = RunWorkoutBackfillReport(
            candidateRuns: candidateCount,
            matched: pairs.count,
            unmatched: candidateCount - pairs.count,
            applied: 0,
            dryRun: dryRun
        )
        print("[RunWorkoutBackfill] \(dryRun ? "dry-run " : "")candidates=\(report.candidateRuns) matched=\(report.matched) unmatched=\(report.unmatched)")
        guard !dryRun else { return report }

        for (run, workout) in pairs {
            if await apply(run, workout) { report.applied += 1 }
        }
        defaults.set(true, forKey: flagKey(for: userID))
        print("[RunWorkoutBackfill] applied=\(report.applied)")
        return report
    }
}

extension TrainingPlanRepository {
    /// Match score of one run against one workout, lower is better. Nil means no match.
    /// A pinned id scores below any heuristic score, so it always wins.
    static func workoutMatchScore(for run: RecordedRun, workout: WorkoutSummary, calendar: Calendar = .current) -> Double? {
        guard run.healthPlanLookupFailed != true, !workout.isComplete else { return nil }
        if let id = run.plannedWorkoutID {
            return workout.id == id ? -1 : nil
        }
        return heuristicMatchScore(for: run, workout: workout, calendar: calendar)
    }

    /// Each run gets at most one workout and each workout at most one run. The closest pair is
    /// taken first, so with two runs on one day the better distance match keeps the workout.
    static func assignRuns(_ runs: [RecordedRun], to workouts: [WorkoutSummary], calendar: Calendar = .current) -> [(RecordedRun, WorkoutSummary)] {
        var candidates: [(run: Int, workout: Int, score: Double)] = []
        for (runIndex, run) in runs.enumerated() {
            for (workoutIndex, workout) in workouts.enumerated() {
                if let score = workoutMatchScore(for: run, workout: workout, calendar: calendar) {
                    candidates.append((runIndex, workoutIndex, score))
                }
            }
        }
        // Stable on ties: earlier run, then earlier workout.
        candidates.sort { ($0.score, $0.run, $0.workout) < ($1.score, $1.run, $1.workout) }
        var usedRuns = Set<Int>()
        var usedWorkouts = Set<Int>()
        var pairs: [(RecordedRun, WorkoutSummary)] = []
        for candidate in candidates where !usedRuns.contains(candidate.run) && !usedWorkouts.contains(candidate.workout) {
            usedRuns.insert(candidate.run)
            usedWorkouts.insert(candidate.workout)
            pairs.append((runs[candidate.run], workouts[candidate.workout]))
        }
        return pairs
    }
}
