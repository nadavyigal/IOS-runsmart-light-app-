import Foundation

/// The one rule for a runner's name. Builds before 1.2.7 saved "RunSmart Runner" when the
/// runner never gave a name, so that placeholder counts as no name everywhere.
nonisolated enum RunnerName {
    static let legacyPlaceholder = "RunSmart Runner"
    static let maxLength = 40

    /// The runner's real name, or nil when there is none.
    static func resolved(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.caseInsensitiveCompare(legacyPlaceholder) != .orderedSame
        else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    /// What to save: the cleaned name, or an empty string when there is none.
    static func forSaving(_ raw: String?) -> String {
        resolved(raw) ?? ""
    }

    /// Today's header: "Good morning, Dana", or just "Good morning" with no name.
    static func greeting(_ greeting: String, name raw: String?) -> String {
        guard let name = resolved(raw) else { return greeting }
        return "\(greeting), \(name)"
    }

    /// Profile and Settings label when a name is needed in the layout.
    static func label(_ raw: String?) -> String {
        resolved(raw) ?? "Runner"
    }
}
