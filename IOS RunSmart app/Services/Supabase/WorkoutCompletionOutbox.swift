import Foundation

private actor WorkoutCompletionRetryGate {
    private var running = false

    func tryEnter() -> Bool {
        if running { return false }
        running = true
        return true
    }

    func leave() {
        running = false
    }
}

struct PendingWorkoutCompletion: Codable, Equatable {
    let workoutID: UUID
    let payload: DBWorkoutCompletionUpdate
    var attemptCount: Int
}

/// Failed workout-completion updates, retried on launch and foreground.
final class WorkoutCompletionOutbox {
    static let shared = WorkoutCompletionOutbox()
    static let maxAttempts = 5

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private let retryGate = WorkoutCompletionRetryGate()
    private var gaveUpIDs: [UUID] = []

    var gaveUpWorkoutIDs: [UUID] {
        lock.lock()
        defer { lock.unlock() }
        return gaveUpIDs
    }

    init(defaults: UserDefaults = .standard, key: String = "runsmart.workouts.pendingCompletions") {
        self.defaults = defaults
        self.key = key
    }

    func pending() -> [PendingWorkoutCompletion] {
        lock.lock()
        defer { lock.unlock() }
        return load()
    }

    func remove(workoutID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        save(load().filter { $0.workoutID != workoutID })
    }

    /// Counts this failure. Drops the record and logs once at `maxAttempts`.
    /// A retry passes `createIfMissing: false` so a success that already removed the record is not queued again.
    func recordFailure(workoutID: UUID, payload: DBWorkoutCompletionUpdate, createIfMissing: Bool = true) {
        lock.lock()
        defer { lock.unlock() }
        var list = load()
        let existing = list.first { $0.workoutID == workoutID }
        if existing == nil && !createIfMissing { return }
        let next = (existing?.attemptCount ?? 0) + 1
        list.removeAll { $0.workoutID == workoutID }
        guard next < Self.maxAttempts else {
            save(list)
            gaveUpIDs.append(workoutID)
            print("[TrainingPlanRepo] giving up on workout completion after \(Self.maxAttempts) attempts workout=\(workoutID)")
            return
        }
        list.append(PendingWorkoutCompletion(workoutID: workoutID, payload: payload, attemptCount: next))
        save(list)
    }

    /// `true` applied, `false` zero rows (done, not retried), `nil` failed and queued.
    func finish(
        workoutID: UUID,
        payload: DBWorkoutCompletionUpdate,
        send: (UUID, DBWorkoutCompletionUpdate) async throws -> Bool
    ) async -> Bool? {
        do {
            let applied = try await send(workoutID, payload)
            remove(workoutID: workoutID)
            return applied
        } catch is CancellationError {
            return nil
        } catch {
            print("[TrainingPlanRepo] completeBestMatchingWorkout error:", error)
            recordFailure(workoutID: workoutID, payload: payload)
            return nil
        }
    }

    /// Zero matching rows is success. A throw increments the attempt count.
    /// A second call returns immediately while one pass is already running.
    func retryPending(
        send: (UUID, DBWorkoutCompletionUpdate) async throws -> Bool
    ) async {
        guard await retryGate.tryEnter() else { return }
        await performRetry(send)
        await retryGate.leave()
    }

    private func performRetry(
        _ send: (UUID, DBWorkoutCompletionUpdate) async throws -> Bool
    ) async {

        for record in pending() {
            do {
                _ = try await send(record.workoutID, record.payload)
                remove(workoutID: record.workoutID)
            } catch is CancellationError {
                continue
            } catch {
                print("[TrainingPlanRepo] completeBestMatchingWorkout error:", error)
                recordFailure(workoutID: record.workoutID, payload: record.payload, createIfMissing: false)
            }
        }
    }

    private func load() -> [PendingWorkoutCompletion] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let raw = try? JSONSerialization.jsonObject(with: data) else {
            print("[TrainingPlanRepo] pending workout completions could not be read as JSON")
            return []
        }
        guard let items = raw as? [Any] else {
            print("[TrainingPlanRepo] pending workout completions were not a list")
            return []
        }
        let decoder = JSONDecoder()
        var records: [PendingWorkoutCompletion] = []
        for item in items {
            guard JSONSerialization.isValidJSONObject(item),
                  let itemData = try? JSONSerialization.data(withJSONObject: item) else {
                print("[TrainingPlanRepo] skipped a pending workout completion that was not an object")
                continue
            }
            do {
                records.append(try decoder.decode(PendingWorkoutCompletion.self, from: itemData))
            } catch {
                print("[TrainingPlanRepo] skipped a pending workout completion:", error)
            }
        }
        return records
    }

    private func save(_ list: [PendingWorkoutCompletion]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: key)
    }
}
