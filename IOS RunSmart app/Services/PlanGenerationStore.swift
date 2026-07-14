import Combine
import Foundation

/// Explicit plan-generation state surfaced on Today and Plan.
///
/// Before WP-43 S1 there was no such state: after onboarding, `saveTrainingGoal`
/// kicked off async generation and Today/Plan simply rendered a blank body /
/// empty calendar for ~30-45s, while the only signal was a transient banner that
/// vanished (audit §4 Risk 1). Today and Plan now always show one of: the
/// generating card, the plan itself, or an inline retry.
enum PlanGenerationState: Equatable {
    case idle
    case generating
    case ready
    case failed

    /// While generating, Today/Plan render the "Coach is building your plan"
    /// card instead of an empty body.
    var showsGeneratingCard: Bool { self == .generating }

    /// On failure the retry lives inline on Today/Plan, not behind a banner
    /// pointing at a Profile-buried screen a new user has never seen.
    var showsInlineRetry: Bool { self == .failed }
}

/// Observes the existing `runSmartPlanGenerationStatusDidChange` notification and
/// maps it to `PlanGenerationState` for the UI.
final class PlanGenerationStore: ObservableObject {
    @Published private(set) var state: PlanGenerationState = .idle

    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?
    private var startedAt: Date?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        // `queue: nil` delivers synchronously on the posting thread. Every post of
        // this notification happens inside `MainActor.run` (SupabaseRunSmartServices),
        // so state updates stay on the main thread — and tests stay deterministic.
        observer = notificationCenter.addObserver(
            forName: .runSmartPlanGenerationStatusDidChange,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let status = note.object as? RunSmartPlanGenerationStatus else { return }
            self?.apply(status)
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    /// Maps the service-level status to the state Today/Plan render.
    static func state(for status: RunSmartPlanGenerationStatus) -> PlanGenerationState {
        switch status {
        case .generating: .generating
        case .amended: .ready
        case .failed: .failed
        }
    }

    /// Called by an inline retry so the card appears immediately, before the
    /// service posts its own `.generating`.
    func markGenerating() {
        apply(.generating)
    }

    private func apply(_ status: RunSmartPlanGenerationStatus) {
        let resolved = Self.state(for: status)
        guard resolved != state else { return }
        state = resolved

        switch resolved {
        case .generating:
            startedAt = Date()
            Analytics.trackPlanGenerationStarted()
        case .ready:
            Analytics.trackPlanGenerationSucceeded(durationMs: elapsedMs())
            startedAt = nil
        case .failed:
            Analytics.trackPlanGenerationFailed(durationMs: elapsedMs())
            startedAt = nil
        case .idle:
            startedAt = nil
        }
    }

    private func elapsedMs() -> Int? {
        guard let startedAt else { return nil }
        return Int(Date().timeIntervalSince(startedAt) * 1000)
    }
}
