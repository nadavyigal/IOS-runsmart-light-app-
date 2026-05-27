import Foundation
import PostHog

// MARK: - Event types

enum FlexWeekCancelStep: String {
    case picker
    case loading
    case diff
}

enum FlexWeekInterventionAction: String {
    case talkToCoach = "talk_to_coach"
    case continueToPicker = "continue_to_picker"
}

// MARK: - Analytics

enum RunSmartAnalytics {
    /// Call once at app startup. Reads keys from Info.plist.
    static func setup() {
        guard
            let apiKey = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String,
            !apiKey.isEmpty
        else { return }
        let host = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String
            ?? "https://us.i.posthog.com"
        let config = PostHogConfig(apiKey: apiKey, host: host)
        PostHogSDK.shared.setup(config)
    }

    // MARK: Flex Week events

    static func flexWeekTriggered(reason: FlexWeekReasonKind, entryPoint: FlexWeekEntryPoint) {
        PostHogSDK.shared.capture(
            "flex_week_triggered",
            properties: [
                "reason": reason.rawValue,
                "entry_point": entryPoint.rawValue,
            ]
        )
    }

    static func flexWeekConfirmed(
        reason: FlexWeekReasonKind,
        source: FlexWeekOutcomeSource,
        changesCount: Int,
        timeToConfirmSeconds: Double
    ) {
        PostHogSDK.shared.capture(
            "flex_week_confirmed",
            properties: [
                "reason": reason.rawValue,
                "source": sourceLabel(source),
                "changes_count": changesCount,
                "time_to_confirm_seconds": Int(timeToConfirmSeconds),
            ]
        )
    }

    static func flexWeekCancelled(step: FlexWeekCancelStep, reason: FlexWeekReasonKind?) {
        var props: [String: Any] = ["step": step.rawValue]
        if let reason { props["reason"] = reason.rawValue }
        PostHogSDK.shared.capture("flex_week_cancelled", properties: props)
    }

    static func flexWeekInterventionShown() {
        PostHogSDK.shared.capture("flex_week_intervention_shown")
    }

    static func flexWeekInterventionAction(_ action: FlexWeekInterventionAction) {
        PostHogSDK.shared.capture(
            "flex_week_intervention_action",
            properties: ["action": action.rawValue]
        )
    }

    private static func sourceLabel(_ source: FlexWeekOutcomeSource) -> String {
        switch source {
        case .ai: "ai"
        case .deterministicFallback: "fallback"
        case .offlineQueued: "offline"
        }
    }
}
