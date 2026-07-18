import Foundation

enum AdaptiveCoachTrigger: String, Hashable {
    case missedWorkout
    case lowRecovery
    case loadSpike
}

struct AdaptiveCoachPrompt: Hashable {
    let trigger: AdaptiveCoachTrigger
    let headline: String
    let detail: String
    let reason: FlexWeekReason
}

/// Decides when the coach proactively proposes a week reshape on Today.
/// Priority: missed workout > load spike > low recovery. One prompt at a
/// time, suppressed for 24h after a dismissal. Thresholds are deliberately
/// stricter than the passive Flex Week link (readiness < 60 in
/// FlexWeekEntryPresentation.shouldShowTodayLink) so the proactive card
/// stays rare and high-signal.
enum AdaptiveCoachPolicy {

    static let lowReadinessThreshold = 45
    static let dismissalCooldownHours = 24

    static func prompt(
        weekWorkouts: [PlannedWorkout],
        readiness: Int,
        loadMetrics: TrainingLoadMetrics,
        lastDismissedAt: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AdaptiveCoachPrompt? {
        if let dismissed = lastDismissedAt,
           let expiry = calendar.date(byAdding: .hour, value: dismissalCooldownHours, to: dismissed),
           now < expiry {
            return nil
        }

        if let missed = FlexWeekPresentation.mostRecentMissedWorkout(in: weekWorkouts, now: now, calendar: calendar) {
            return AdaptiveCoachPrompt(
                trigger: .missedWorkout,
                headline: "Missed \(missed.title)?",
                detail: "I can reshape the rest of this week so you stay on track — nothing changes until you approve it.",
                reason: .missedWorkout(workoutID: missed.id)
            )
        }

        if loadMetrics.status == .highRisk {
            return AdaptiveCoachPrompt(
                trigger: .loadSpike,
                headline: "Your training load jumped",
                detail: "This week is much bigger than your recent month. I can ease the next few days to lower injury risk.",
                reason: .tired
            )
        }

        if readiness > 0 && readiness < lowReadinessThreshold {
            return AdaptiveCoachPrompt(
                trigger: .lowRecovery,
                headline: "Recovery is running low",
                detail: "Readiness is \(readiness). I can soften this week so you rebuild before the next hard session.",
                reason: .tired
            )
        }

        return nil
    }
}

/// Visibility policy for the Adaptive Coach card: flag AND prompt, nothing
/// else. Kept here (not in the SwiftUI file) because it is pure logic.
enum AdaptiveCoachPresentation {
    static func shouldShow(flagEnabled: Bool, prompt: AdaptiveCoachPrompt?) -> Bool {
        flagEnabled && prompt != nil
    }
}
