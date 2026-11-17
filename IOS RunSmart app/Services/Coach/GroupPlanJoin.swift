import Foundation

/// A4 copy. The wording is "replaces", never "archived".
enum GroupPlanConfirmCopy {
    static let building = "Building your plan…"
    static let generationFailed = "We couldn't build your plan. You're not linked yet."
    static let cancel = "Cancel"
    static let retry = "Retry"

    static func title(coach: String) -> String {
        "\(coach)'s group plan"
    }

    static func detailsLine(_ settings: GroupPlanSettings, calendar: Calendar = .current) -> String {
        let date = raceLabel(settings.raceDate, calendar: calendar)
        let distance = GroupPlanRules.distanceTitle(settings.targetDistance)
        let level = GroupPlanRules.levelTitle(settings.level)
        return "\(distance) · Race \(date) · \(level) · \(settings.runsPerWeek) runs a week"
    }

    static func replaces(_ summary: String) -> String {
        "This replaces your current plan (\(summary))."
    }

    static func useButton(coach: String) -> String {
        "Use \(coach)'s plan"
    }

    static func joinFailed(coach: String) -> String {
        "Couldn't connect you to \(coach). Nothing was shared."
    }

    static func currentPlanSummary(
        _ plan: TrainingPlanSnapshot,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let week = TrainingMetrics.currentWeekNumber(
            planStartDate: plan.startDate,
            totalWeeks: plan.totalWeeks,
            now: today,
            calendar: calendar
        )
        let label = plan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(label.isEmpty ? "Current plan" : label), week \(week)"
    }

    private static func raceLabel(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}

/// The request Build my plan's generator receives for one group-plan join.
enum GroupPlanRequest {
    static func make(
        settings: GroupPlanSettings,
        profile: OnboardingProfile,
        today: Date,
        calendar: Calendar = .current
    ) -> TrainingGoalRequest {
        let window = GroupPlanRules.planWindow(raceDate: settings.raceDate, today: today, calendar: calendar)
        let preferred = profile.preferredDays.isEmpty ? ["Mon", "Wed", "Sat"] : profile.preferredDays
        let tone = profile.coachingTone.isEmpty ? "Motivating" : profile.coachingTone
        return TrainingGoalRequest(
            displayName: profile.displayName,
            goal: settings.goal,
            experience: settings.level,
            age: profile.age,
            averageWeeklyDistanceKm: profile.averageWeeklyDistanceKm,
            trainingDataSource: profile.trainingDataSource,
            weeklyRunDays: settings.runsPerWeek,
            preferredDays: preferred,
            coachingTone: tone,
            targetDate: calendar.startOfDay(for: settings.raceDate),
            explicitTargetDistance: settings.targetDistance,
            planStartDate: window.startDate,
            planWeekCount: window.weeks
        )
    }
}

enum GroupPlanJoinFailure: Equatable {
    case generation
    case join
}

struct GroupPlanConfirm: Equatable {
    var coach: CoachLookup
    var athleteID: UUID
    var settings: GroupPlanSettings
    /// Nil when the athlete has no current plan. The replace sentence is omitted.
    var replacement: String?
    var failure: GroupPlanJoinFailure?
    /// True after the new plan exists. A later Retry joins again and does not generate.
    var planBuilt: Bool
}

enum JoinCoachFollowUp: Equatable {
    case today
    case buildMyPlan
}

/// One row of `lookup_invite`. Missing plan columns stay nil so an older
/// database still decodes and keeps Story 1.3's immediate join.
struct CoachInviteLookupRow: Decodable, Equatable {
    let inviteId: UUID
    let coachId: UUID
    let displayName: String
    let planMode: String?
    let goal: String?
    let targetDistance: String?
    let raceDate: String?
    let level: String?
    let runsPerWeek: Int?

    enum CodingKeys: String, CodingKey {
        case inviteId = "invite_id"
        case coachId = "coach_id"
        case displayName = "display_name"
        case planMode = "plan_mode"
        case goal
        case targetDistance = "target_distance"
        case raceDate = "race_date"
        case level
        case runsPerWeek = "runs_per_week"
    }

    func coachLookup(code: String) -> CoachLookup {
        CoachLookup(
            inviteID: inviteId,
            coachID: coachId,
            displayName: displayName,
            code: code,
            planMode: planMode.flatMap(CoachPlanMode.init(rawValue:)),
            groupPlan: groupSettings
        )
    }

    private var groupSettings: GroupPlanSettings? {
        guard planMode == CoachPlanMode.group.rawValue,
              let goal, let targetDistance, let raceDate, let level, let runsPerWeek,
              let date = GroupPlanSettings.raceDate(from: raceDate)
        else { return nil }
        return GroupPlanSettings(
            goal: goal,
            targetDistance: targetDistance,
            raceDate: date,
            level: level,
            runsPerWeek: runsPerWeek
        )
    }
}

/// The athlete's own plan, read and written under their login. The coach never writes it.
@MainActor
protocol GroupPlanAthleteContext: AnyObject {
    func profile() -> OnboardingProfile
    func activePlan() async -> TrainingPlanSnapshot?
    func isActivePlanConfirmedMissing() async -> Bool
    func generateAndPersist(_ request: TrainingGoalRequest) async -> Bool
}

@MainActor
final class LiveGroupPlanContext: GroupPlanAthleteContext {
    private let services: any RunSmartServiceProviding
    private let profileSource: () -> OnboardingProfile

    init(services: any RunSmartServiceProviding, profile: @escaping () -> OnboardingProfile) {
        self.services = services
        self.profileSource = profile
    }

    func profile() -> OnboardingProfile { profileSource() }

    func activePlan() async -> TrainingPlanSnapshot? {
        await services.activeTrainingPlan()
    }

    func isActivePlanConfirmedMissing() async -> Bool {
        await services.isActivePlanConfirmedMissing()
    }

    func generateAndPersist(_ request: TrainingGoalRequest) async -> Bool {
        await services.regenerateTrainingPlan(request)
    }
}
