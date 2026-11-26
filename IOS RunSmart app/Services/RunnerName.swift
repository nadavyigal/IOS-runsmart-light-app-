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
    /// The name is isolated (FSI ... PDI) so a Hebrew name never reorders the comma.
    static func greeting(_ greeting: String, name raw: String?) -> String {
        guard let name = resolved(raw) else { return greeting }
        return BidiText.fill("\(greeting), {Runner}", ["Runner": name])
    }

    /// Profile and Settings label when a name is needed in the layout.
    static func label(_ raw: String?) -> String {
        resolved(raw) ?? "Runner"
    }
}

/// The one-time "What should we call you?" card on Today, for runners who finished
/// onboarding before the app asked for a name. Dismissing it is remembered per account;
/// the small "Add your name" link under the greeting stays until a name is saved.
nonisolated enum RunnerNamePrompt {
    static let keyPrefix = "runsmart.runnerNamePrompt.dismissed."

    static func dismissedKey(userID: UUID?) -> String {
        keyPrefix + (userID?.uuidString.lowercased() ?? "signed-out")
    }

    static func shouldShow(name: String?, hasCompletedOnboarding: Bool, dismissed: Bool) -> Bool {
        hasCompletedOnboarding && !dismissed && RunnerName.resolved(name) == nil
    }

    static func isDismissed(userID: UUID?, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: dismissedKey(userID: userID))
    }

    static func dismiss(userID: UUID?, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: dismissedKey(userID: userID))
    }
}
