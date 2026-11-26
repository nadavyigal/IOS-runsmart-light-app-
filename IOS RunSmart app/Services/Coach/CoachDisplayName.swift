import Foundation
import Supabase

/// The coach's own name, as athletes see it in My coach, coach notes and pushes
/// (`coach_profiles.display_name`). The server checks the same rules in
/// `public.set_coach_display_name` (20261126100000_coach_display_name.sql).
nonisolated enum CoachDisplayName {
    /// Server limit: `char_length(name) <= 40`, which counts code points.
    static let maxLength = 40
    /// Names the app shows when there is no name. Saving one of them would hide the gap.
    static let placeholders: Set<String> = ["coach", "your coach", "athlete", "runsmart runner"]

    /// The coach's real name, or nil when it is blank or a placeholder.
    static func resolved(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
              !placeholders.contains(trimmed.lowercased())
        else { return nil }
        return trimmed
    }

    /// The name to send, or nil when the server would reject it.
    static func forSaving(_ raw: String) -> String? {
        guard let name = resolved(raw), BidiText.fits(name, limit: maxLength) else { return nil }
        return name
    }

    /// Cuts typing at the server limit without splitting a character.
    static func capped(_ raw: String) -> String {
        guard !BidiText.fits(raw, limit: maxLength) else { return raw }
        var kept = ""
        for character in raw {
            guard BidiText.fits(kept + String(character), limit: maxLength) else { break }
            kept.append(character)
        }
        return kept
    }
}

nonisolated protocol CoachDisplayNameSaving: Sendable {
    /// Saves the caller's coach name and returns what the server stored.
    func save(_ name: String) async throws -> String
}

nonisolated struct SupabaseCoachDisplayNameService: CoachDisplayNameSaving {
    private struct Params: Encodable, Sendable {
        let p_name: String
    }

    func save(_ name: String) async throws -> String {
        try await SupabaseManager.client
            .rpc("set_coach_display_name", params: Params(p_name: name))
            .execute()
            .value
    }
}
