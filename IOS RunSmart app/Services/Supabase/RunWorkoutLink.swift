import Foundation

/// Natural key of a `runs` row: the same pair the upsert conflicts on.
struct RunSourceKey: Codable, Hashable {
    let sourceProvider: String
    let sourceActivityID: String
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

enum RunWorkoutLinkResult: Equatable {
    case linked
    /// The run already has a workout. Nothing was changed.
    case alreadyLinked
    /// No `runs` row yet. The run has not synced.
    case runNotSynced
    /// Another run owns this workout (unique index). Never relinked.
    case workoutTaken
}

struct PendingRunLink: Codable, Equatable {
    let authUserID: UUID
    let key: RunSourceKey
    let workoutID: UUID
    let queuedAt: Date
    var attemptCount: Int
}

/// Run-to-workout links that could not be written yet (offline, or the run row is not synced).
/// A miss is never queued: only a match whose write failed or whose run is not on the server yet.
final class RunWorkoutLinkOutbox {
    static let shared = RunWorkoutLinkOutbox()
    static let maxAttempts = 5
    /// A run that never reaches the server stops holding a record after this long.
    static let maxAge: TimeInterval = 14 * 24 * 3600

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private let retryGate = WorkoutCompletionRetryGate()
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, key: String = "runsmart.runs.pendingWorkoutLinks", now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.key = key
        self.now = now
    }

    func pending() -> [PendingRunLink] {
        lock.lock()
        defer { lock.unlock() }
        return load()
    }

    /// One record per run: a newer match for the same run replaces the old one.
    func enqueue(authUserID: UUID, key runKey: RunSourceKey, workoutID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var list = load().filter { !($0.authUserID == authUserID && $0.key == runKey) }
        list.append(PendingRunLink(authUserID: authUserID, key: runKey, workoutID: workoutID, queuedAt: now(), attemptCount: 0))
        save(list)
    }

    func remove(_ record: PendingRunLink) {
        lock.lock()
        defer { lock.unlock() }
        save(load().filter { !($0.authUserID == record.authUserID && $0.key == record.key) })
    }

    /// A thrown write counts one attempt and drops the record at `maxAttempts`.
    /// Only counts against a record that is still queued: a failure never re-adds one a success removed.
    func recordFailure(_ record: PendingRunLink) {
        lock.lock()
        defer { lock.unlock() }
        var list = load()
        guard let index = list.firstIndex(where: { $0.authUserID == record.authUserID && $0.key == record.key }) else { return }
        list[index].attemptCount += 1
        if list[index].attemptCount >= Self.maxAttempts {
            print("[TrainingPlanRepo] giving up on run link after \(Self.maxAttempts) attempts workout=\(record.workoutID)")
            list.remove(at: index)
        }
        save(list)
    }

    /// Retries every record. `runNotSynced` keeps the record without counting an attempt until it expires.
    /// A second call returns immediately while one pass is already running.
    func retryPending(send: (PendingRunLink) async throws -> RunWorkoutLinkResult) async {
        guard await retryGate.tryEnter() else { return }
        await performRetry(send)
        await retryGate.leave()
    }

    private func performRetry(_ send: (PendingRunLink) async throws -> RunWorkoutLinkResult) async {
        for record in pending() {
            if now().timeIntervalSince(record.queuedAt) > Self.maxAge {
                print("[TrainingPlanRepo] dropping run link for a run that never synced workout=\(record.workoutID)")
                remove(record)
                continue
            }
            do {
                switch try await send(record) {
                case .linked, .alreadyLinked, .workoutTaken: remove(record)
                case .runNotSynced: continue
                }
            } catch is CancellationError {
                continue
            } catch {
                print("[TrainingPlanRepo] run link retry error:", error)
                recordFailure(record)
            }
        }
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

private actor RunWorkoutBackfillGate {
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

/// One-off, per-install link of the signed-in user's recent synced runs to plan workouts.
enum RunWorkoutBackfill {
    static let lookbackDays = 30
    static let dryRunDefaultsKey = "runsmart.debug.runWorkoutBackfillDryRun"
    private static let gate = RunWorkoutBackfillGate()

    /// The flag is per account, so a second account on the same install still gets its pass.
    static func flagKey(for userID: UUID) -> String {
        "runsmart.runs.workoutLinkBackfill.v1.\(userID.uuidString)"
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
        apply: (RecordedRun, WorkoutSummary) async -> Bool
    ) async -> RunWorkoutBackfillReport? {
        guard !defaults.bool(forKey: flagKey(for: userID)) else { return nil }
        guard await gate.tryEnter() else { return nil }
        let report = await perform(
            userID: userID, defaults: defaults, dryRun: dryRun, calendar: calendar,
            loadRuns: loadRuns, loadWorkouts: loadWorkouts, apply: apply
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
        apply: (RecordedRun, WorkoutSummary) async -> Bool
    ) async -> RunWorkoutBackfillReport? {
        guard let runs = await loadRuns(), let workouts = await loadWorkouts() else { return nil }
        let pairs = TrainingPlanRepository.assignRuns(runs, to: workouts, calendar: calendar)
        var report = RunWorkoutBackfillReport(
            candidateRuns: runs.count,
            matched: pairs.count,
            unmatched: runs.count - pairs.count,
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
