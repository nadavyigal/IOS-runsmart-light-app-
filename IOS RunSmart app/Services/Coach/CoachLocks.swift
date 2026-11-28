import Foundation
import Supabase

// C8.5: the athlete side and the AI respect coach locks (M6a `workouts.locked`,
// M6b `plans.coach_published`). The database triggers are the backstop; this file
// keeps the app from offering, sending or showing raw errors for blocked writes.

/// Server error messages from the M6a/M6b migrations that the app maps to copy.
enum CoachLockError: String, CaseIterable, Sendable {
    case workoutLocked = "workout_locked"
    case planLockedByCoach = "plan_locked_by_coach"
    case coachWorkoutsPresent = "coach_workouts_present"
    case countChanged = "count_changed"
    case dateTaken = "date_taken"

    static func classify(_ error: Error) -> CoachLockError? {
        let text: String
        if let postgrest = error as? PostgrestError {
            text = postgrest.message
        } else {
            text = String(describing: error)
        }
        return allCases.first { text.contains($0.rawValue) }
    }

    /// PostgREST's "function not found": the RPC is not deployed yet (Batch C not applied).
    static func isMissingFunction(_ error: Error) -> Bool {
        if let postgrest = error as? PostgrestError {
            return postgrest.code == "PGRST202" || postgrest.message.contains("Could not find the function")
        }
        let text = String(describing: error)
        return text.contains("PGRST202") || text.contains("Could not find the function")
    }

    /// What the athlete sees. Nil: no lock copy (the caller keeps its own failure).
    var notice: CoachLockNotice? {
        switch self {
        case .workoutLocked: .workoutLocked
        case .planLockedByCoach: .planLocked
        case .dateTaken: .dateTaken
        // C7.9 owns the counted warning for these two.
        case .coachWorkoutsPresent, .countChanged: nil
        }
    }
}

/// A blocked write the athlete must be told about. Shown by `CoachLockNoticeHost`.
enum CoachLockNotice: String, Equatable, Identifiable, Sendable {
    case workoutLocked
    case planLocked
    case dateTaken

    var id: String { rawValue }
}

extension Notification.Name {
    /// `object` is a `CoachLockNotice`. Posted on the main thread.
    static let runSmartCoachLockNotice = Notification.Name("runSmartCoachLockNotice")
}

enum CoachLockNotices {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastPlanLock: Date?

    /// True right after a plan write was blocked by a coach-published plan, so a caller
    /// that only gets `false` back (the goal wizard) can leave the P5 block to explain.
    static func planLockedRecently(within seconds: TimeInterval = 10, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let lastPlanLock else { return false }
        return now.timeIntervalSince(lastPlanLock) < seconds
    }

    static func post(_ notice: CoachLockNotice, center: NotificationCenter = .default) {
        if notice == .planLocked {
            lock.lock()
            lastPlanLock = Date()
            lock.unlock()
        }
        Task { @MainActor in
            center.post(name: .runSmartCoachLockNotice, object: notice)
        }
    }

    /// Posts the notice for `error` when it is a lock error. Returns the lock error, if any.
    @discardableResult
    static func postIfLock(_ error: Error, center: NotificationCenter = .default) -> CoachLockError? {
        guard let lock = CoachLockError.classify(error) else { return nil }
        if let notice = lock.notice { post(notice, center: center) }
        return lock
    }
}

/// Exact copy from C8.5 AC 6 / AC 7 (spec §C.5 P3–P5) and C8.15 AC 7. Names are bidi-isolated.
enum CoachLockCopy {
    static let fallbackCoachName = "Your coach"

    /// [ASSUMPTION copy; Sally light review]
    static func workoutLocked(coach: String) -> String {
        BidiText.fill("{Coach} set this workout, so it can't be changed here.", ["Coach": coach])
    }

    static let dateTaken = "That day already has a workout."

    static func planLockedTitle(coach: String) -> String {
        BidiText.fill("Ask {Coach} to change your plan", ["Coach": coach])
    }

    static func planLockedBody(coach: String) -> String {
        BidiText.fill("{Coach} manages your goal and plan. To change your race, date or runs per week, ask {Coach}.", ["Coach": coach])
    }

    static func replyToLatestNote(coach: String) -> String {
        BidiText.fill("Reply to {Coach}'s latest note", ["Coach": coach])
    }

    static let ok = "OK"

    /// P3 lock tag.
    static func setBy(coach: String) -> String {
        BidiText.fill("Set by {Coach}", ["Coach": coach])
    }

    static func coachName(_ link: CoachLink?) -> String {
        let name = link?.coachName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? fallbackCoachName : name
    }
}

enum CoachLockRules {
    /// C8.5 AC 2 / AC 4, client side: whatever produced the outcome (AI, cache or the
    /// deterministic builder), a coach-locked row keeps its original values, no other
    /// workout moves onto a locked row's day (a coach rest day included), and changes
    /// to those rows are dropped. With no locked rows the outcome is returned as is.
    static func respectingLocks(_ outcome: FlexWeekOutcome, originalWeek: [PlannedWorkout], calendar: Calendar = .current) -> FlexWeekOutcome {
        let lockedRows = originalWeek.filter(\.coachLocked)
        guard !lockedRows.isEmpty else { return outcome }
        let lockedIDs = Set(lockedRows.map(\.id))
        let lockedDays = Set(lockedRows.map { calendar.startOfDay(for: $0.scheduledDate) })
        let originals = Dictionary(originalWeek.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var reverted = Set<UUID>()
        let week = outcome.restructuredWeek.map { workout -> PlannedWorkout in
            guard let original = originals[workout.id] else { return workout }
            if lockedIDs.contains(workout.id) { return original }
            let moved = !calendar.isDate(workout.scheduledDate, inSameDayAs: original.scheduledDate)
            if moved, lockedDays.contains(calendar.startOfDay(for: workout.scheduledDate)) {
                reverted.insert(workout.id)
                return original
            }
            return workout
        }
        let changes = outcome.changes.filter { change in
            if lockedIDs.contains(change.workoutID) || reverted.contains(change.workoutID) { return false }
            if let from = change.originalWorkoutID, lockedIDs.contains(from) { return false }
            return true
        }
        return FlexWeekOutcome(
            restructuredWeek: week,
            changes: changes,
            safetyWarnings: outcome.safetyWarnings,
            source: outcome.source
        )
    }

    /// Locked rows dated on or after `today`, as M6b's `coach_plan_locked_future_count`
    /// counts them (it uses the athlete's time zone; this uses the phone's). C7.9 shows
    /// this number before a replacement.
    static func lockedFutureCount(_ workouts: [DBWorkout], today: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: today)
        return workouts.filter { workout in
            guard workout.locked, let date = workout.scheduledDateAsDate else { return false }
            return date >= start
        }.count
    }

    /// AC 8: an open (not yet handled) pain flag of this athlete.
    static func hasOpenPainFlag(_ flags: [AthleteRunFlag], ownerID: UUID?) -> Bool {
        guard let ownerID else { return false }
        return flags.contains { $0.ownerID == ownerID && $0.kind == .pain && $0.resolvedAt == nil }
    }
}
