import CryptoKit
import Foundation
import Supabase

// C7.16 one-tap praise. A reaction is an ordinary coach note on the run or week (the existing
// `coach_add_feedback` RPC and `CoachFeedbackOutbox`), so it is stored with the coach's own words,
// shown to the athlete as a coach note, and never AI-written. It is stored as kind 'note' (the
// existing default of `coach_feedback.kind`), so there is no schema change: the milestone key lives on the phone.

nonisolated enum CoachMilestoneReactions {
    /// The note id for one reaction. It depends only on the coach and the milestone, so a double tap,
    /// a retry after a dropped connection and a second phone all send the same id, and the server's
    /// "same id returns the stored row" rule makes a second reaction impossible.
    static func feedbackID(coachID: UUID, milestoneID: String) -> UUID {
        let digest = SHA256.hash(data: Data("coach-milestone-reaction|\(coachID.uuidString.lowercased())|\(milestoneID)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5 layout
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// Which milestones this coach already reacted to, kept on the phone per coach. It is set the moment
/// the coach taps, before the send finishes, so "Reacted" shows at once and survives a relaunch.
nonisolated struct CoachMilestoneReactionStore: @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(_ coachID: UUID) -> String { "coachMilestone.reacted.v1.\(coachID.uuidString.lowercased())" }

    func reacted(coachID: UUID) -> Set<String> {
        Set(defaults.stringArray(forKey: key(coachID)) ?? [])
    }

    func add(_ milestoneID: String, coachID: UUID) {
        var all = reacted(coachID: coachID)
        all.insert(milestoneID)
        defaults.set(Array(all).sorted(), forKey: key(coachID))
    }

    func remove(_ milestoneID: String, coachID: UUID) {
        var all = reacted(coachID: coachID)
        all.remove(milestoneID)
        defaults.set(Array(all).sorted(), forKey: key(coachID))
    }
}

/// The runs and weeks this coach already wrote feedback on, per athlete (keys are
/// `CoachFeedbackTarget.key`). A note written from the composer or from another phone counts too.
nonisolated protocol CoachMilestoneReactionReading: Sendable {
    func feedbackTargets(athleteIDs: [UUID]) async throws -> [UUID: Set<String>]
}

nonisolated struct SupabaseCoachMilestoneReactionReader: CoachMilestoneReactionReading {
    private struct Row: Decodable {
        let athleteID: UUID
        let runID: Int64?
        let weekStart: String?

        enum CodingKeys: String, CodingKey {
            case athleteID = "athlete_id"
            case runID = "run_id"
            case weekStart = "week_start"
        }
    }

    func feedbackTargets(athleteIDs: [UUID]) async throws -> [UUID: Set<String>] {
        guard !athleteIDs.isEmpty else { return [:] }
        // RLS already limits this to the signed-in coach's notes on actively linked athletes.
        let rows: [Row] = try await SupabaseManager.client
            .from(CoachFeedbackRPC.table)
            .select("athlete_id,run_id,week_start")
            .in("athlete_id", values: athleteIDs.map(\.uuidString))
            .execute()
            .value
        var result: [UUID: Set<String>] = [:]
        for row in rows {
            if let run = row.runID { result[row.athleteID, default: []].insert(CoachFeedbackTarget.run(run).key) }
            if let week = row.weekStart { result[row.athleteID, default: []].insert(CoachFeedbackTarget.week(week).key) }
        }
        return result
    }
}
