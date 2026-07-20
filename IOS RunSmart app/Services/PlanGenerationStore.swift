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
            // Posts currently always happen inside `MainActor.run`, so this runs
            // synchronously on main. Hop defensively anyway: a future background
            // post would otherwise mutate `@Published` off-main and crash SwiftUI.
            if Thread.isMainThread {
                self?.apply(status)
            } else {
                DispatchQueue.main.async { self?.apply(status) }
            }
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
            trackOutcome(Analytics.trackPlanGenerationSucceeded)
        case .failed:
            trackOutcome(Analytics.trackPlanGenerationFailed)
        case .idle:
            startedAt = nil
        }
    }

    /// Emits a terminal plan-generation event at most once per observed
    /// generation, and only for generations this store actually saw start.
    ///
    /// This store's job is UI state; it was doubling as the analytics emitter for
    /// the generation lifecycle, so *any* terminal state transition produced a
    /// funnel event. On founder device `0efa0d1b` (07-14/07-15) that surfaced as
    /// six `plan_generation_failed`/`plan_generation_succeeded` pairs 19ms apart:
    /// two terminal notifications arriving back to back — `saveTrainingGoal` posts
    /// one per call and is reachable from six call sites — each flipped the state
    /// and each emitted. One of every pair was lying about a generation that
    /// never happened.
    ///
    /// Consuming `startedAt` fixes both halves: the second post of a pair finds no
    /// in-flight generation and stays silent, and `duration_ms` is now always
    /// present rather than nil-when-unmatched. Deliberate consequence: a terminal
    /// status with no observed start (e.g. a background regeneration completing
    /// into a fresh store) emits nothing, which keeps started -> succeeded/failed
    /// a closed funnel instead of one whose numerator can exceed its denominator.
    private func trackOutcome(_ track: (Int?) -> Void) {
        guard startedAt != nil else { return }
        let durationMs = elapsedMs()
        startedAt = nil
        track(durationMs)
    }

    private func elapsedMs() -> Int? {
        guard let startedAt else { return nil }
        return Int(Date().timeIntervalSince(startedAt) * 1000)
    }
}
