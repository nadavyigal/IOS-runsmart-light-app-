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

    func profileReference(fallback: UUID) -> DBProfileReference {
        if let numericUserID { return .numeric(numericUserID) }
        return .uuid(profileUUID ?? fallback)
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

extension DBPlan {
    var startDateAsDate: Date? {
        ISO8601DateFormatter.shortDate.date(from: startDate)
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
    private static let profileDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

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

        if let numericID = resolved.numericUserID,
           let active = await activePlanByNumericProfile(numericProfileID: numericID) {
            print("[TrainingPlanRepo] ✅ found active plan via numeric profileID=\(numericID)")
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

    func activePlanByNumericProfile(numericProfileID: Int) async -> ActivePlan? {
        do {
            let plans: [DBPlan] = try await supabase
                .from("plans")
                .select()
                .eq("profile_id", value: numericProfileID)
                .eq("is_active", value: true)
                .limit(1)
                .execute()
                .value

            print("[TrainingPlanRepo] activePlan numeric profileID=\(numericProfileID) plans=\(plans.count)")
            guard let plan = plans.first else { return nil }

            let workouts: [DBWorkout] = try await supabase
                .from("workouts")
                .select()
                .eq("plan_id", value: plan.id.uuidString)
                .order("scheduled_date")
                .execute()
                .value

            print("[TrainingPlanRepo] activePlan numeric planID=\(plan.id) workouts=\(workouts.count)")
            return ActivePlan(plan: plan, workouts: workouts)
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] activePlan numeric error:", error)
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
                age: request.age,
                averageWeeklyDistanceKm: request.averageWeeklyDistanceKm,
                trainingDataSource: request.trainingDataSource?.rawValue,
                trainingDataUpdatedAt: request.averageWeeklyDistanceKm.map { _ in Self.profileDateFormatter.string(from: Date()) },
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
                print("[TrainingPlanRepo] saveTrainingGoal rich update error:", error)
            }
            do {
                try await supabase
                    .from("profiles")
                    .update(DBProfileGoalUpdateLegacy(
                        name: request.displayName,
                        goal: request.supabaseGoal,
                        experience: request.supabaseExperience,
                        preferredTimes: request.preferredDays,
                        daysPerWeek: request.weeklyRunDays,
                        coachingStyle: request.supabaseCoachingStyle,
                        onboardingComplete: true
                    ))
                    .eq("auth_user_id", value: authUserID.uuidString)
                    .execute()
                return true
            } catch {
                if !(error is CancellationError) {
                    print("[TrainingPlanRepo] saveTrainingGoal legacy update error:", error)
                }
                return false
            }
        }
    }

    func persistGeneratedPlan(authUserID: UUID, request: TrainingGoalRequest, generated: RunSmartDTO.GeneratedPlan) async -> Bool {
        let resolved = await identity(authUserID: authUserID)
        let profileID = resolved.profileReference(fallback: authUserID)
        print("[TrainingPlanRepo] persistGeneratedPlan using profileID=\(profileID.debugValue)")

        do {
            switch profileID {
            case .numeric(let value):
                try await supabase
                    .from("plans")
                    .update(DBPlanActiveUpdate(isActive: false))
                    .eq("profile_id", value: value)
                    .eq("is_active", value: true)
                    .execute()
            case .uuid(let value):
                try await supabase
                    .from("plans")
                    .update(DBPlanActiveUpdate(isActive: false))
                    .eq("profile_id", value: value.uuidString)
                    .eq("is_active", value: true)
                    .execute()
            case .string(let value):
                try await supabase
                    .from("plans")
                    .update(DBPlanActiveUpdate(isActive: false))
                    .eq("profile_id", value: value)
                    .eq("is_active", value: true)
                    .execute()
            }

            let startDate = Date()
            let totalWeeks = max(1, min(16, generated.totalWeeks))
            let endDate = Calendar.current.date(byAdding: .day, value: totalWeeks * 7, to: startDate) ?? request.targetDate
            let planRows: [DBPlan] = try await supabase
                .from("plans")
                .insert(DBPlanInsert(
                    profileID: profileID,
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

            print("[TrainingPlanRepo] ✅ persisted generated plan=\(plan.id) workouts=\(workouts.count) profileID=\(profileID.debugValue)")
            return true
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] ❌ persistGeneratedPlan error:", error)
            }
            return false
        }
    }

    func saveSuggestedWorkout(authUserID: UUID, suggestion: StructuredNextWorkout, report: RunReportDetail) async -> Bool {
        guard let active = await activePlan(authUserID: authUserID) else {
            print("[TrainingPlanRepo] saveSuggestedWorkout failed: no active plan")
            return false
        }

        let targetDate = Self.suggestedWorkoutDate(suggestion.dateLabel)
        let day = Self.dayLabel(for: targetDate)
        let planStart = active.plan.startDateAsDate ?? Date()
        let week = max(1, Calendar.current.dateComponents([.weekOfYear], from: planStart, to: targetDate).weekOfYear.map { $0 + 1 } ?? 1)
        let type = Self.suggestedWorkoutType(title: suggestion.title)
        let distance = Self.distanceKm(from: suggestion.distance) ?? Self.distanceKm(from: suggestion.title) ?? 0
        let notes = [suggestion.notes, suggestion.target, "Suggested from \(report.title) on \(report.dateLabel)"]
            .compactMap { value -> String? in
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return value
            }
            .joined(separator: "\n")

        let insert = DBWorkoutInsert(
            planID: active.plan.id.uuidString,
            authUserID: authUserID.uuidString,
            week: week,
            day: day,
            type: type,
            distance: distance,
            duration: Self.durationMinutes(from: suggestion),
            pace: Self.paceSecondsPerKm(from: suggestion.target),
            completed: false,
            scheduledDate: ISO8601DateFormatter.shortDate.string(from: targetDate),
            notes: notes.isEmpty ? nil : notes,
            workoutStructure: suggestion.notes,
            intensity: suggestion.target,
            trainingPhase: "coach-recommendation"
        )

        do {
            try await supabase
                .from("workouts")
                .insert(insert)
                .execute()
            print("[TrainingPlanRepo] ✅ saved suggested workout plan=\(active.plan.id) date=\(insert.scheduledDate) type=\(type)")
            return true
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] saveSuggestedWorkout error:", error)
            }
            return false
        }
    }

    func completeBestMatchingWorkout(authUserID: UUID, for run: RecordedRun) async -> WorkoutSummary? {
        guard let active = await activePlan(authUserID: authUserID) else { return nil }
        let candidates = active.workouts
            .filter { !$0.completed }
            .map { $0.toWorkoutSummary() }

        guard let match = Self.bestWorkoutMatch(for: run, in: candidates) else { return nil }
        do {
            try await supabase
                .from("workouts")
                .update(DBWorkoutCompletionUpdate(completed: true))
                .eq("id", value: match.id.uuidString)
                .execute()
            var completed = match
            completed.isComplete = true
            print("[TrainingPlanRepo] ✅ completed workout=\(match.id) from run=\(run.consolidatedActivityID ?? run.providerActivityID ?? run.id.uuidString)")
            return completed
        } catch {
            if !(error is CancellationError) {
                print("[TrainingPlanRepo] completeBestMatchingWorkout error:", error)
            }
            return nil
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

    static func suggestedWorkoutDate(_ label: String?) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty else {
            return tomorrow
        }

        if let isoDate = ISO8601DateFormatter.shortDate.date(from: label) {
            return isoDate
        }

        let formatters: [DateFormatter] = ["MMM d, yyyy", "MMMM d, yyyy", "MMM d", "MMMM d", "EEEE", "EEE"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.defaultDate = Date()
            return formatter
        }

        for formatter in formatters {
            if var date = formatter.date(from: label) {
                if !label.contains(String(Calendar.current.component(.year, from: Date()))) {
                    let year = calendar.component(.year, from: Date())
                    var components = calendar.dateComponents([.month, .day, .weekday], from: date)
                    components.year = year
                    date = calendar.date(from: components) ?? date
                    if date < calendar.startOfDay(for: Date()) {
                        date = calendar.date(byAdding: .year, value: 1, to: date) ?? date
                    }
                }
                return calendar.startOfDay(for: date)
            }
        }

        return tomorrow
    }

    static func suggestedWorkoutType(title: String) -> String {
        let value = title.lowercased()
        if value.contains("interval") { return "intervals" }
        if value.contains("tempo") || value.contains("threshold") { return "tempo" }
        if value.contains("hill") { return "hill" }
        if value.contains("long") { return "long" }
        if value.contains("recover") || value.contains("rest") { return "recovery" }
        if value.contains("strength") { return "strength" }
        if value.contains("race") { return "race-pace" }
        return "easy"
    }

    static func distanceKm(from value: String?) -> Double? {
        guard let value else { return nil }
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        guard let match = normalized.range(of: #"(\d+(\.\d+)?)"#, options: .regularExpression) else {
            return nil
        }
        return Double(normalized[match])
    }

    static func durationMinutes(from suggestion: StructuredNextWorkout) -> Int? {
        let source = [suggestion.notes, suggestion.target, suggestion.title].compactMap { $0 }.joined(separator: " ")
        guard let match = source.range(of: #"(\d+)\s*(min|minute)"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let text = String(source[match])
        guard let numberRange = text.range(of: #"\d+"#, options: .regularExpression) else {
            return nil
        }
        return Int(text[numberRange])
    }

    static func paceSecondsPerKm(from value: String?) -> Int? {
        guard let value,
              let match = value.range(of: #"(\d{1,2}):(\d{2})"#, options: .regularExpression) else {
            return nil
        }
        let parts = value[match].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    static func bestWorkoutMatch(for run: RecordedRun, in workouts: [WorkoutSummary], calendar: Calendar = .current) -> WorkoutSummary? {
        let sameDay = workouts.filter { workout in
            !workout.isComplete && calendar.isDate(workout.scheduledDate, inSameDayAs: run.startedAt)
        }
        guard !sameDay.isEmpty else { return nil }

        let runKm = run.distanceMeters / 1_000
        let runMinutes = run.movingTimeSeconds / 60
        let scored = sameDay.compactMap { workout -> (WorkoutSummary, Double)? in
            let plannedKm = distanceKm(from: workout.distance)
            let plannedMinutes = workout.durationMinutes.map(Double.init)
            var score = 0.0

            if let plannedKm, plannedKm > 0, runKm > 0 {
                let distanceDelta = abs(plannedKm - runKm)
                guard distanceDelta <= max(1.5, plannedKm * 0.35) else { return nil }
                score += distanceDelta
            } else {
                score += 1.0
            }

            if let plannedMinutes, plannedMinutes > 0, runMinutes > 0 {
                let minuteDelta = abs(plannedMinutes - runMinutes)
                guard minuteDelta <= max(15, plannedMinutes * 0.40) else { return nil }
                score += minuteDelta / 10
            }

            if workout.kind == .recovery || workout.kind == .strength {
                score += 2.5
            }

            return (workout, score)
        }

        return scored.min(by: { $0.1 < $1.1 })?.0
    }

    private static func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
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
    let age: Int?
    let averageWeeklyDistanceKm: Double?
    let trainingDataSource: String?
    let trainingDataUpdatedAt: String?
    let preferredTimes: [String]
    let daysPerWeek: Int
    let coachingStyle: String
    let onboardingComplete: Bool

    enum CodingKeys: String, CodingKey {
        case name, goal, experience, age
        case averageWeeklyDistanceKm = "average_weekly_distance_km"
        case trainingDataSource = "training_data_source"
        case trainingDataUpdatedAt = "training_data_updated_at"
        case preferredTimes = "preferred_times"
        case daysPerWeek = "days_per_week"
        case coachingStyle = "coaching_style"
        case onboardingComplete = "onboarding_complete"
    }
}

private struct DBProfileGoalUpdateLegacy: Encodable {
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
    let profileID: DBProfileReference
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

private struct DBWorkoutCompletionUpdate: Encodable {
    let completed: Bool
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
