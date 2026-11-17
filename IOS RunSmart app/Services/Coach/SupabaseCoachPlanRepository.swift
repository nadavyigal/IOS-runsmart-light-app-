import Foundation
import Supabase

nonisolated struct SupabaseCoachPlanRepository: CoachPlanRepository {
    private struct PlanRow: Decodable {
        let planMode: String?

        enum CodingKeys: String, CodingKey {
            case planMode = "plan_mode"
        }
    }

    private struct GroupPlanRow: Decodable {
        let goal: String
        let targetDistance: String
        let raceDate: String
        let level: String
        let runsPerWeek: Int

        enum CodingKeys: String, CodingKey {
            case goal
            case targetDistance = "target_distance"
            case raceDate = "race_date"
            case level
            case runsPerWeek = "runs_per_week"
        }
    }

    private struct ModeParams: Encodable {
        let mode: String
    }

    private struct SettingsParams: Encodable {
        let goal: String
        let targetDistance: String
        let raceDate: String
        let level: String
        let runsPerWeek: Int

        enum CodingKeys: String, CodingKey {
            case goal
            case targetDistance = "target_distance"
            case raceDate = "race_date"
            case level
            case runsPerWeek = "runs_per_week"
        }
    }

    func loadPlanSetup() async throws -> CoachPlanSetup {
        let rows: [PlanRow] = try await SupabaseManager.client
            .from("coach_profiles")
            .select("plan_mode")
            .limit(1)
            .execute()
            .value
        let mode = rows.first?.planMode.flatMap(CoachPlanMode.init(rawValue:))

        let plans: [GroupPlanRow] = try await SupabaseManager.client
            .from("coach_group_plans")
            .select("goal,target_distance,race_date,level,runs_per_week")
            .limit(1)
            .execute()
            .value
        let groupPlan = plans.first.flatMap { row -> GroupPlanSettings? in
            guard let date = GroupPlanSettings.raceDate(from: row.raceDate) else { return nil }
            return GroupPlanSettings(
                goal: row.goal,
                targetDistance: row.targetDistance,
                raceDate: date,
                level: row.level,
                runsPerWeek: row.runsPerWeek
            )
        }
        return CoachPlanSetup(mode: mode, groupPlan: groupPlan)
    }

    func setPlanMode(_ mode: CoachPlanMode) async throws {
        try await SupabaseManager.client
            .rpc("set_plan_mode", params: ModeParams(mode: mode.rawValue))
            .execute()
    }

    func saveGroupPlan(_ settings: GroupPlanSettings) async throws {
        let params = SettingsParams(
            goal: settings.goal,
            targetDistance: settings.targetDistance,
            raceDate: settings.raceDateString(),
            level: settings.level,
            runsPerWeek: settings.runsPerWeek
        )
        try await SupabaseManager.client
            .rpc("save_group_plan_settings", params: params)
            .execute()
    }
}
