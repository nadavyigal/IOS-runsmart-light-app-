import Foundation

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
    private(set) var gaveUpWorkoutIDs: [UUID] = []

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
    func recordFailure(workoutID: UUID, payload: DBWorkoutCompletionUpdate) {
        lock.lock()
        defer { lock.unlock() }
        var list = load()
        let previous = list.first { $0.workoutID == workoutID }?.attemptCount ?? 0
        let next = previous + 1
        list.removeAll { $0.workoutID == workoutID }
        guard next < Self.maxAttempts else {
            save(list)
            gaveUpWorkoutIDs.append(workoutID)
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
    func retryPending(
        send: (UUID, DBWorkoutCompletionUpdate) async throws -> Bool
    ) async {
        for record in pending() {
            do {
                _ = try await send(record.workoutID, record.payload)
                remove(workoutID: record.workoutID)
            } catch is CancellationError {
                continue
            } catch {
                print("[TrainingPlanRepo] completeBestMatchingWorkout error:", error)
                recordFailure(workoutID: record.workoutID, payload: record.payload)
            }
        }
    }

    private func load() -> [PendingWorkoutCompletion] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([PendingWorkoutCompletion].self, from: data) else { return [] }
        return list
    }

    private func save(_ list: [PendingWorkoutCompletion]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: key)
    }
}
