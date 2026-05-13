import Foundation
import Supabase

public struct TrainingPlanRepository {
    let client: SupabaseClient

    public init(client: SupabaseClient) {
        self.client = client
    }

    // Fetches the active training plan by numeric profile ID
    public func activePlanByNumericProfile(_ numericProfileID: Int) async throws -> TrainingPlan? {
        // Use `.filter` instead of `.eq` to ensure numeric filter is sent correctly to PostgREST
        let response = try await client.database
            .from("plans")
            .select()
            .filter("profile_id", operator: .eq, value: numericProfileID)
            .eq("is_active", true)
            .execute()

        if let data = response.data, !data.isEmpty {
            let plans = try data.compactMap { try JSONDecoder().decode(TrainingPlan.self, from: $0) }
            if let plan = plans.first {
                print("[TrainingPlanRepo] ✅ found active plan via numeric profileID=\(numericProfileID)")
                return plan
            }
        }

        print("[TrainingPlanRepo] no active plan found via numeric profileID=\(numericProfileID)")
        return nil
    }

    // Fetches the active training plan for a user ID (UUID string)
    public func activePlan(authUserID: String) async throws -> TrainingPlan? {
        let identity = try await resolveIdentity(authUserID: authUserID)
        print("[TrainingPlanRepo] identity auth=\(authUserID) profileUUID=\(String(describing: identity.profileUUID)) numericUserID=\(String(describing: identity.numericUserID))")

        // Bail out early if no profile identifiers
        guard let profileUUID = identity.profileUUID ?? nil, let numericUserID = identity.numericUserID ?? nil else {
            print("[TrainingPlanRepo] no profileUUID or numericUserID found, skipping activePlan lookup")
            return nil
        }

        if let numericID = numericUserID {
            if let plan = try await activePlanByNumericProfile(numericID) {
                return plan
            }
        }

        // Optionally, can also add UUID lookup here if needed
        // For now, only numeric lookup is handled to reduce log spam

        return nil
    }

    // Resolves identity for a user: returns optional profileUUID and numericUserID
    private func resolveIdentity(authUserID: String) async throws -> (profileUUID: UUID?, numericUserID: Int?) {
        // Example identity resolver: fetch user profile info from database
        let response = try await client.database
            .from("profiles")
            .select(columns: "id, numeric_id")
            .eq("auth_id", authUserID)
            .single()
            .execute()

        guard let data = response.data else {
            return (nil, nil)
        }

        let profileUUID = UUID(uuidString: data["id"] as? String ?? "")
        let numericUserID = data["numeric_id"] as? Int

        return (profileUUID, numericUserID)
    }
}

// Model for TrainingPlan (example)
public struct TrainingPlan: Codable {
    public let id: UUID
    public let profile_id: Int
    public let is_active: Bool
    // add other properties as needed
}
