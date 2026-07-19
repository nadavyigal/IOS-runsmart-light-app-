import Foundation

/// Local feature flags, Info.plist-driven (same pattern as the other
/// RUNSMART_* Info keys and RunSmartDemoMode's launch-argument overrides).
/// Default OFF: a missing or non-affirmative value never enables a flag.
enum RunSmartFeatureFlags {

    /// Adaptive Coach proactive Today card (Phase 1). Ships dark; flips via
    /// RUNSMART_ADAPTIVE_COACH_ENABLED = YES in a release, or the
    /// -RUNSMART_ADAPTIVE_COACH launch argument for QA sessions.
    static var adaptiveCoachEnabled: Bool {
        adaptiveCoachEnabled(
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            processArguments: ProcessInfo.processInfo.arguments
        )
    }

    static func adaptiveCoachEnabled(
        infoDictionary: [String: Any],
        processArguments: [String]
    ) -> Bool {
        if processArguments.contains("-RUNSMART_ADAPTIVE_COACH") { return true }
        let raw = (infoDictionary["RUNSMART_ADAPTIVE_COACH_ENABLED"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return raw == "YES" || raw == "TRUE" || raw == "1"
    }
}
