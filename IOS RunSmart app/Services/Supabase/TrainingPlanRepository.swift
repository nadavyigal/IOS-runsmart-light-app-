import Foundation
import Supabase
import SwiftUI

// MARK: - Active plan bundle

struct ActivePlan {
    let plan: DBPlan
    let workouts: [DBWorkout]

    var todayWorkout: DBWorkout? {
        let todayDate = ISO8601DateFormatter.shortDate.string(from: Date())
        return workouts.first { $0.scheduledDate == todayDate && !$0.completed }
            ?? workouts.first { $0.scheduledDate == todayDate }
    }

    var nextActionableWorkout: DBWorkout? {
        let today = Calendar.current.startOfDay(for: Date())
        return workouts
            .filter { workout in
                guard let date = workout.scheduledDateAsDate else { return false }
                return date >= today && !workout.completed
            }
            .sorted { ($0.scheduledDateAsDate ?? .distantFuture) < ($1.scheduledDateAsDate ?? .distantFuture) }
            .first
    }

    var currentWeekWorkouts: [DBWorkout] {
        let calendar = Calendar.current
        let today = Date()
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today)
        return workouts.filter { w in
            guard let date = w.scheduledDateAsDate else { return false }
            return weekInterval?.contains(date) == true
        }
    }

    var completedKmThisWeek: Double {
        currentWeekWorkouts.filter { $0.completed }.reduce(0) { $0 + $1.distance }
    }

    var totalKmThisWeek: Double {
        currentWeekWorkouts.reduce(0) { $0 + $1.distance }
    }
}

struct RunSmartIdentity: Sendable {
    let authUserID: UUID
    let profileUUID: UUID?
    let numericUserID: Int?

    var planOwnerCandidates: [UUID] {
        var values: [UUID] = []
        if let profileUUID, profileUUID != authUserID { values.append(profileUUID) }
        values.append(authUserID)
        return values
    }
}

private struct DBProfileIdentity: Decodable, Sendable {
    let profileUUID: UUID?
    let numericUserID: Int?
    let authUserID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case authUserID = "auth_user_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? c.decode(UUID.self, forKey: .id) {
            profileUUID = uuid
            numericUserID = nil
        } else if let int = try? c.decode(Int.self, forKey: .id) {
            profileUUID = nil
            numericUserID = int
        } else if let string = try? c.decode(String.self, forKey: .id), let uuid = UUID(uuidString: string) {
            profileUUID = uuid
            numericUserID = nil
        } else if let string = try? c.decode(String.self, forKey: .id), let int = Int(string) {
            profileUUID = nil
            numericUserID = int
        } else {
            profileUUID = nil
            numericUserID = nil
        }
        authUserID = try? c.decodeIfPresent(UUID.self, forKey: .authUserID)
    }
}

extension DBWorkout {
    var scheduledDateAsDate: Date? {
        ISO8601DateFormatter.shortDate.date(from: scheduledDate)
    }
}

extension Array where Element == DBWorkout {
    func primaryWorkoutPerDay() -> [DBWorkout] {
        let grouped = Dictionary(grouping: self, by: \.scheduledDate)
        return grouped.values.compactMap { workouts in
            workouts.sorted { lhs, rhs in
                if lhs.completed != rhs.completed { return !lhs.completed }
                return lhs.priorityScore > rhs.priorityScore
            }.first
        }
        .sorted { ($0.scheduledDateAsDate ?? .distantFuture) < ($1.scheduledDateAsDate ?? .distantFuture) }
    }
}

private extension DBWorkout {
    var priorityScore: Int {
        switch workoutKind {
        case .long: 8
        case .intervals, .tempo, .hills: 7
        case .race: 6
        case .easy, .parkrun: 5
        case .recovery: 3
        case .strength: 2
        }
    }
}

extension ISO8601DateFormatter {
    static let shortDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}

// MARK: - Repository

final class TrainingPlanRepository {
    private let supabase = SupabaseManager.client

    func identity(authUserID: UUID) async -> RunSmartIdentity {
        do {
            let rows: [DBProfileIdentity] = try await supabase
                .from("profiles")
                .select("id,auth_user_id")
                .eq("auth_user_id", value: authUserID.uuidString)
                .limit(1)
                .execute()
                .value

            let row = rows.first
            let canonicalPlanOwner = row?.profileUUID ?? row?.authUserID
            let identity = RunSmartIdentity(
                authUserID: authUserID,
                profileUUID: canonicalPlanOwner,
                numericUserID: row?.numericUserID
            )
            print("[TrainingPlanRepo] identity auth=\(authUserID) profileUUID=\(identity.profileUUID?.uuidString ?? "nil") numericUserID=\(identity.numericUserID.map(String.init) ?? "nil")")
            return identity
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] identity error:", error)
            }
            return RunSmartIdentity(authUserID: authUserID, profileUUID: nil, numericUserID: nil)
        }
    }

    func activePlan(authUserID: UUID) async -> ActivePlan? {
        let resolved = await identity(authUserID: authUserID)

        if let active = await activePlanByAuthUserID(authUserID) {
            print("[TrainingPlanRepo] ✅ found active plan via auth_user_id=\(authUserID)")
            return active
        }

        if resolved.planOwnerCandidates.isEmpty {
            print("[TrainingPlanRepo] ❌ identity unresolved for auth=\(authUserID)")
            return nil
        }

        for ownerID in resolved.planOwnerCandidates {
            if let active = await activePlan(profileID: ownerID) {
                print("[TrainingPlanRepo] ✅ found active plan via UUID profileID=\(ownerID)")
                return active
            }
        }

        print("[TrainingPlanRepo] ❌ no active plan for auth=\(authUserID) tried numeric=\(resolved.numericUserID.map(String.init) ?? "nil") UUIDs=\(resolved.planOwnerCandidates.map(\.uuidString))")
        return nil
    }

    func activePlanByAuthUserID(_ authUserID: UUID) async -> ActivePlan? {
        do {
            let plans: [DBPlan] = try await supabase
                .from("plans")
                .select()
                .eq("auth_user_id", value: authUserID.uuidString)
                .eq("is_active", value: true)
                .limit(1)
                .execute()
                .value

            print("[TrainingPlanRepo] activePlan authUserID=\(authUserID) plans=\(plans.count)")
            guard let plan = plans.first else { return nil }

            let workouts: [DBWorkout] = try await supabase
                .from("workouts")
                .select()
                .eq("plan_id", value: plan.id.uuidString)
                .order("scheduled_date")
                .execute()
                .value

            print("[TrainingPlanRepo] activePlan auth planID=\(plan.id) workouts=\(workouts.count)")
            return ActivePlan(plan: plan, workouts: workouts)
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] activePlan auth error:", error)
            }
            return nil
        }
    }

    func activePlan(profileID: UUID) async -> ActivePlan? {
        do {
            let plans: [DBPlan] = try await supabase
                .from("plans")
                .select()
                .eq("profile_id", value: profileID.uuidString)
                .eq("is_active", value: true)
                .limit(1)
                .execute()
                .value

            print("[TrainingPlanRepo] activePlan UUID profileID=\(profileID) plans=\(plans.count)")
            guard let plan = plans.first else { return nil }

            let workouts: [DBWorkout] = try await supabase
                .from("workouts")
                .select()
                .eq("plan_id", value: plan.id.uuidString)
                .order("scheduled_date")
                .execute()
                .value

            print("[TrainingPlanRepo] activePlan planID=\(plan.id) workouts=\(workouts.count)")
            return ActivePlan(plan: plan, workouts: workouts)
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] activePlan UUID error:", error)
            }
            return nil
        }
    }
    func planWorkouts(authUserID: UUID, from startDate: Date, to endDate: Date) async -> [DBWorkout] {
        guard let plan = await activePlan(authUserID: authUserID) else { return [] }
        return await workouts(planID: plan.plan.id, from: startDate, to: endDate)
    }

    func workouts(planID: UUID, from startDate: Date, to endDate: Date) async -> [DBWorkout] {
        do {
            let startStr = ISO8601DateFormatter.shortDate.string(from: startDate)
            let endStr = ISO8601DateFormatter.shortDate.string(from: endDate)

            let workouts: [DBWorkout] = try await supabase
                .from("workouts")
                .select()
                .eq("plan_id", value: planID.uuidString)
                .gte("scheduled_date", value: startStr)
                .lte("scheduled_date", value: endStr)
                .order("scheduled_date")
                .execute()
                .value

            return workouts
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] planWorkouts error:", error)
            }
            return []
        }
    }

    func saveTrainingGoal(authUserID: UUID, request: TrainingGoalRequest) async -> Bool {
        do {
            let update = DBProfileGoalUpdate(
                name: request.displayName,
                goal: request.supabaseGoal,
                experience: request.supabaseExperience,
                preferredTimes: request.preferredDays,
                daysPerWeek: request.weeklyRunDays,
                coachingStyle: request.supabaseCoachingStyle,
                onboardingComplete: true
            )

            try await supabase
                .from("profiles")
                .update(update)
                .eq("auth_user_id", value: authUserID.uuidString)
                .execute()
            return true
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] saveTrainingGoal error:", error)
            }
            return false
        }
    }

    func persistGeneratedPlan(authUserID: UUID, request: TrainingGoalRequest, generated: RunSmartDTO.GeneratedPlan) async -> Bool {
        let resolved = await identity(authUserID: authUserID)
        let profileIDValue = (resolved.profileUUID ?? authUserID).uuidString
        print("[TrainingPlanRepo] persistGeneratedPlan using UUID profileID=\(profileIDValue)")

        do {
            try await supabase
                .from("plans")
                .update(DBPlanActiveUpdate(isActive: false))
                .eq("profile_id", value: profileIDValue)
                .eq("is_active", value: true)
                .execute()

            let startDate = Date()
            let totalWeeks = max(1, min(16, generated.totalWeeks))
            let endDate = Calendar.current.date(byAdding: .day, value: totalWeeks * 7, to: startDate) ?? request.targetDate
            let planRows: [DBPlan] = try await supabase
                .from("plans")
                .insert(DBPlanInsert(
                    profileID: profileIDValue,
                    authUserID: authUserID.uuidString,
                    title: generated.title,
                    description: generated.description,
                    startDate: ISO8601DateFormatter.shortDate.string(from: startDate),
                    endDate: ISO8601DateFormatter.shortDate.string(from: endDate),
                    totalWeeks: totalWeeks,
                    isActive: true,
                    planType: "basic",
                    trainingDaysPerWeek: request.weeklyRunDays,
                    targetDistance: generated.targetDistance,
                    targetTime: generated.targetTime,
                    peakWeeklyVolume: generated.peakWeeklyVolume
                ))
                .select()
                .execute()
                .value

            guard let plan = planRows.first else {
                print("[TrainingPlanRepo] ❌ persistGeneratedPlan failed: no plan returned after insert")
                return false
            }

            let workouts = generated.workouts.map {
                DBWorkoutInsert(
                    planID: plan.id.uuidString,
                    authUserID: authUserID.uuidString,
                    week: $0.week,
                    day: $0.day,
                    type: $0.type,
                    distance: $0.distance,
                    duration: $0.duration,
                    pace: $0.pace,
                    completed: false,
                    scheduledDate: scheduledDate(startDate: startDate, week: $0.week, day: $0.day),
                    notes: $0.notes,
                    workoutStructure: $0.workoutStructure,
                    intensity: $0.intensity,
                    trainingPhase: $0.trainingPhase
                )
            }

            if !workouts.isEmpty {
                try await supabase
                    .from("workouts")
                    .insert(workouts)
                    .execute()
            }

            print("[TrainingPlanRepo] ✅ persisted generated plan=\(plan.id) workouts=\(workouts.count) profileID=\(profileIDValue)")
            return true
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] ❌ persistGeneratedPlan error:", error)
            }
            return false
        }
    }

    func amendWorkout(workoutID: UUID, patch: WorkoutPatch) async -> Bool {
        do {
            try await supabase
                .from("workouts")
                .update(DBWorkoutUpdate(patch: patch))
                .eq("id", value: workoutID.uuidString)
                .execute()
            return true
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] amendWorkout error:", error)
            }
            return false
        }
    }

    func moveWorkout(workoutID: UUID, to date: Date) async -> Bool {
        await amendWorkout(workoutID: workoutID, patch: WorkoutPatch(scheduledDate: date))
    }

    func pushWorkoutTomorrow(workoutID: UUID) async -> Bool {
        guard let workout = await workout(id: workoutID) else {
            print("[TrainingPlanRepo] pushWorkoutTomorrow failed: workout not found \(workoutID)")
            return false
        }

        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        let targetDate = ISO8601DateFormatter.shortDate.string(from: tomorrow)

        do {
            let conflicts: [DBWorkout] = try await supabase
                .from("workouts")
                .select()
                .eq("plan_id", value: workout.planId.uuidString)
                .eq("scheduled_date", value: targetDate)
                .eq("completed", value: false)
                .execute()
                .value

            if let conflict = conflicts.first(where: { $0.id != workoutID }) {
                let nextDay = calendar.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow
                _ = await moveWorkout(workoutID: conflict.id, to: nextDay)
                print("[TrainingPlanRepo] pushWorkoutTomorrow cascaded conflict=\(conflict.id)")
            }

            return await moveWorkout(workoutID: workoutID, to: tomorrow)
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] pushWorkoutTomorrow error:", error)
            }
            return false
        }
    }

    func removeWorkout(workoutID: UUID) async -> Bool {
        do {
            try await supabase
                .from("workouts")
                .delete()
                .eq("id", value: workoutID.uuidString)
                .execute()
            return true
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] removeWorkout error:", error)
            }
            return false
        }
    }

    private func scheduledDate(startDate: Date, week: Int, day: String) -> String {
        let dayMap = ["Sun": 1, "Mon": 2, "Tue": 3, "Wed": 4, "Thu": 5, "Fri": 6, "Sat": 7]
        var date = Calendar.current.date(byAdding: .day, value: max(0, week - 1) * 7, to: startDate) ?? startDate
        let target = dayMap[day] ?? Calendar.current.component(.weekday, from: date)
        let current = Calendar.current.component(.weekday, from: date)
        let delta = (target - current + 7) % 7
        date = Calendar.current.date(byAdding: .day, value: delta, to: date) ?? date
        return ISO8601DateFormatter.shortDate.string(from: date)
    }

    private func workout(id: UUID) async -> DBWorkout? {
        do {
            let workouts: [DBWorkout] = try await supabase
                .from("workouts")
                .select()
                .eq("id", value: id.uuidString)
                .limit(1)
                .execute()
                .value
            return workouts.first
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] workout lookup error:", error)
            }
            return nil
        }
    }
}

private struct DBProfileGoalUpdate: Encodable {
    let name: String
    let goal: String
    let experience: String
    let preferredTimes: [String]
    let daysPerWeek: Int
    let coachingStyle: String
    let onboardingComplete: Bool

    enum CodingKeys: String, CodingKey {
        case name, goal, experience
        case preferredTimes = "preferred_times"
        case daysPerWeek = "days_per_week"
        case coachingStyle = "coaching_style"
        case onboardingComplete = "onboarding_complete"
    }
}

private struct DBPlanActiveUpdate: Encodable {
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
    }
}

private struct DBPlanInsert: Encodable {
    let profileID: String
    let authUserID: String
    let title: String
    let description: String?
    let startDate: String
    let endDate: String
    let totalWeeks: Int
    let isActive: Bool
    let planType: String
    let trainingDaysPerWeek: Int
    let targetDistance: Double?
    let targetTime: Int?
    let peakWeeklyVolume: Double?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case authUserID = "auth_user_id"
        case title, description
        case startDate = "start_date"
        case endDate = "end_date"
        case totalWeeks = "total_weeks"
        case isActive = "is_active"
        case planType = "plan_type"
        case trainingDaysPerWeek = "training_days_per_week"
        case targetDistance = "target_distance"
        case targetTime = "target_time"
        case peakWeeklyVolume = "peak_weekly_volume"
    }
}

private struct DBWorkoutInsert: Encodable {
    let planID: String
    let authUserID: String
    let week: Int
    let day: String
    let type: String
    let distance: Double
    let duration: Int?
    let pace: Int?
    let completed: Bool
    let scheduledDate: String
    let notes: String?
    let workoutStructure: String?
    let intensity: String?
    let trainingPhase: String?

    enum CodingKeys: String, CodingKey {
        case planID = "plan_id"
        case authUserID = "auth_user_id"
        case week, day, type, distance, duration, pace, completed
        case scheduledDate = "scheduled_date"
        case notes
        case workoutStructure = "workout_structure"
        case intensity
        case trainingPhase = "training_phase"
    }
}

private struct DBWorkoutUpdate: Encodable {
    let scheduledDate: String?
    let day: String?
    let type: String?
    let distance: Double?
    let duration: Int?
    let pace: Int?
    let notes: String?
    let workoutStructure: String?

    init(patch: WorkoutPatch) {
        scheduledDate = patch.scheduledDate.map { ISO8601DateFormatter.shortDate.string(from: $0) }
        day = patch.scheduledDate.map { date in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }
        type = patch.kind?.supabaseType
        distance = patch.distanceKm
        duration = patch.durationMinutes
        pace = patch.targetPaceSecondsPerKm
        notes = patch.notes
        workoutStructure = patch.workoutStructure
    }

    enum CodingKeys: String, CodingKey {
        case scheduledDate = "scheduled_date"
        case day, type, distance, duration, pace, notes
        case workoutStructure = "workout_structure"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(scheduledDate, forKey: .scheduledDate)
        try c.encodeIfPresent(day, forKey: .day)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(distance, forKey: .distance)
        try c.encodeIfPresent(duration, forKey: .duration)
        try c.encodeIfPresent(pace, forKey: .pace)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(workoutStructure, forKey: .workoutStructure)
    }
}

// MARK: - DBWorkout → WorkoutSummary

extension DBWorkout {
    func toWorkoutSummary() -> WorkoutSummary {
        let date = scheduledDateAsDate ?? Date()
        let calendar = Calendar.current
        let weekdayIndex = calendar.component(.weekday, from: date) - 1
        let weekday = calendar.shortWeekdaySymbols[weekdayIndex].uppercased()
        let dayNum = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)

        return WorkoutSummary(
            id: id,
            scheduledDate: date,
            planID: planId,
            weekday: weekday,
            date: "\(dayNum)",
            kind: workoutKind,
            title: workoutTitle,
            distance: distance > 0 ? String(format: "%.1f km", distance) : (duration.map { "\($0) min" } ?? "--"),
            detail: notes ?? "",
            isToday: isToday,
            isComplete: completed,
            durationMinutes: duration,
            targetPaceSecondsPerKm: pace,
            intensity: intensity,
            trainingPhase: trainingPhase,
            workoutStructure: workoutStructure
        )
    }

    var workoutKind: WorkoutKind {
        switch type {
        case "easy": return .easy
        case "tempo", "race-pace", "fartlek": return .tempo
        case "intervals": return .intervals
        case "hill", "hills": return .hills
        case "long": return .long
        case "race": return .race
        case "parkrun": return .parkrun
        case "recovery", "rest": return .recovery
        default: return .easy
        }
    }

    var workoutTitle: String {
        switch type {
        case "easy": return String(format: "Easy %.0f km", distance)
        case "tempo": return String(format: "Tempo %.0f km", distance)
        case "race-pace": return String(format: "Race Pace %.0f km", distance)
        case "intervals": return "Interval Session"
        case "hill": return "Hill Repeats"
        case "long": return String(format: "Long Run %.0f km", distance)
        case "recovery": return "Recovery Run"
        case "rest": return "Rest Day"
        case "fartlek": return "Fartlek Run"
        default: return type.capitalized
        }
    }

    var paceLabel: String {
        guard let paceSeconds = pace, paceSeconds > 0 else { return "--:--" }
        let mins = paceSeconds / 60
        let secs = paceSeconds % 60
        return String(format: "%d:%02d", Int32(mins), Int32(secs))
    }
}
