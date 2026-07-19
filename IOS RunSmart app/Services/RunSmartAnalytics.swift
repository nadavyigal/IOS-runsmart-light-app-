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
    case cancelled
}

enum AdaptiveCoachAnalyticsAction: String {
    case review
    case dismiss
}

// MARK: - Analytics

enum RunSmartAnalytics {
    /// Call once at app startup. Reads keys from Info.plist.
    static func setup() {
#if DEBUG
        guard !RunSmartDemoMode.isEnabled else { return }
#endif
        guard
            let projectToken = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String,
            !projectToken.isEmpty
        else { return }
        let host = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String
            ?? "https://us.i.posthog.com"
        let config = PostHogConfig(projectToken: projectToken, host: host)
        PostHogSDK.shared.setup(config)
    }

    // MARK: Flex Week events

    static func flexWeekTriggered(reason: FlexWeekReasonKind, entryPoint: FlexWeekEntryPoint) {
#if DEBUG
        guard !RunSmartDemoMode.isEnabled else { return }
#endif
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
#if DEBUG
        guard !RunSmartDemoMode.isEnabled else { return }
#endif
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
#if DEBUG
        guard !RunSmartDemoMode.isEnabled else { return }
#endif
        var props: [String: Any] = ["step": step.rawValue]
        if let reason { props["reason"] = reason.rawValue }
        PostHogSDK.shared.capture("flex_week_cancelled", properties: props)
    }

    static func flexWeekInterventionShown() {
#if DEBUG
        guard !RunSmartDemoMode.isEnabled else { return }
#endif
        PostHogSDK.shared.capture("flex_week_intervention_shown")
    }

    static func flexWeekInterventionAction(_ action: FlexWeekInterventionAction) {
#if DEBUG
        guard !RunSmartDemoMode.isEnabled else { return }
#endif
        PostHogSDK.shared.capture(
            "flex_week_intervention_action",
            properties: ["action": action.rawValue]
        )
    }

    static func adaptiveCoachShown(trigger: AdaptiveCoachTrigger) {
#if DEBUG
        guard !RunSmartDemoMode.isEnabled else { return }
#endif
        PostHogSDK.shared.capture(
            "adaptive_coach_shown",
            properties: ["trigger": trigger.rawValue]
        )
    }

    static func adaptiveCoachAction(_ action: AdaptiveCoachAnalyticsAction, trigger: AdaptiveCoachTrigger) {
#if DEBUG
        guard !RunSmartDemoMode.isEnabled else { return }
#endif
        PostHogSDK.shared.capture(
            "adaptive_coach_action",
            properties: ["action": action.rawValue, "trigger": trigger.rawValue]
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
