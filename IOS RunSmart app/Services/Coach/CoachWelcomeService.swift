import Foundation
import Supabase

nonisolated struct CoachWelcomeSettings: Decodable, Sendable {
    let coachName: String
    let savedText: String?
    let canEdit: Bool

    enum CodingKeys: String, CodingKey {
        case coachName = "coach_name"
        case savedText = "saved_text"
        case canEdit = "can_edit"
    }
}

nonisolated protocol CoachWelcomeServing: Sendable {
    func settings(athleteID: UUID?) async throws -> CoachWelcomeSettings
    func save(_ text: String, athleteID: UUID?) async throws
    func claim() async throws
}

nonisolated struct SupabaseCoachWelcomeService: CoachWelcomeServing {
    private struct Athlete: Encodable, Sendable {
        let p_athlete: UUID
    }

    private struct Template: Encodable, Sendable {
        let p_text: String
    }

    private struct Override: Encodable, Sendable {
        let p_athlete: UUID
        let p_text: String
    }

    func settings(athleteID: UUID?) async throws -> CoachWelcomeSettings {
        let client = await SupabaseManager.client
        if let athleteID {
            return try await client.rpc("get_coach_welcome", params: Athlete(p_athlete: athleteID))
                .single().execute().value
        }
        return try await client.rpc("get_coach_welcome").single().execute().value
    }

    func save(_ text: String, athleteID: UUID?) async throws {
        let client = await SupabaseManager.client
        if let athleteID {
            try await client.rpc("coach_set_athlete_welcome", params: Override(p_athlete: athleteID, p_text: text))
                .execute()
        } else {
            try await client.rpc("set_welcome_template", params: Template(p_text: text)).execute()
        }
    }

    func claim() async throws {
        try await SupabaseManager.client.rpc("claim_welcome_note").execute()
    }
}
