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

/// Why a plan generation failed, sent as `reason` on `plan_generation_failed`.
///
/// Before this the event carried only `duration_ms`, so the one real-runner
/// failure (16 Oct, 1.1.8) could only be blamed on a 401 by its 2.8 s timing.
enum PlanGenerationFailureReason: String, Equatable {
    case noSession = "no_session"
    case authRequired = "auth_required"
    case requestRejected = "request_rejected"
    case serverError = "server_error"
    case network
    case badResponse = "bad_response"
    case noPlan = "no_plan"
    case persistFailed = "persist_failed"
    case cancelled
    case unknown

    /// The `userInfo` key the `.failed` status post carries this under.
    static let userInfoKey = "reason"

    static func classify(_ error: Error) -> PlanGenerationFailureReason {
        switch error {
        case is CancellationError:
            return .cancelled
        case RunSmartAPIError.badStatus(let status):
            switch status {
            case 401, 403: return .authRequired
            case 500...: return .serverError
            default: return .requestRejected
            }
        case let urlError as URLError:
            return urlError.code == .cancelled ? .cancelled : .network
        case is DecodingError:
            return .badResponse
        default:
            return .unknown
        }
    }

    /// For a decoded response with no plan. The API client returns the decoded
    /// body even on a non-2xx status, so a 401 lands here, not in `classify(_ error:)`.
    static func classify(_ response: RunSmartDTO.GeneratePlanResponse) -> PlanGenerationFailureReason {
        response.code == "AUTH_REQUIRED" ? .authRequired : .noPlan
    }
}

/// Which plan card Today and Plan show, if any.
///
/// `PlanGenerationState` lives in memory, so a relaunch turns `.failed` back into
/// `.idle`. On 16 Oct a real runner's first plan failed (1.1.8, bare-domain
/// redirect dropped the token); after relaunch Today offered only "Ask Coach",
/// and 13 days later they still had no plan. `buildMissingPlan` gives that
/// runner a way back that survives a relaunch.
enum PlanGenerationCard: Equatable {
    case generating
    case retry
    case buildMissingPlan

    /// `planConfirmedMissing` must be true only when a lookup *succeeded* and
    /// found no active plan. A failed lookup also yields no plan, and offering
    /// to build one then could replace a plan the runner has.
    static func resolve(
        generation: PlanGenerationState,
        planConfirmedMissing: Bool,
        hasCompletedOnboarding: Bool
    ) -> PlanGenerationCard? {
        switch generation {
        case .generating: return .generating
        case .failed: return .retry
        case .ready: return nil
        case .idle:
            return planConfirmedMissing && hasCompletedOnboarding ? .buildMissingPlan : nil
        }
    }
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
            let reason = note.userInfo?[PlanGenerationFailureReason.userInfoKey] as? PlanGenerationFailureReason
            // Posts currently always happen inside `MainActor.run`, so this runs
            // synchronously on main. Hop defensively anyway: a future background
            // post would otherwise mutate `@Published` off-main and crash SwiftUI.
            if Thread.isMainThread {
                self?.apply(status, reason: reason)
            } else {
                DispatchQueue.main.async { self?.apply(status, reason: reason) }
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

    private func apply(_ status: RunSmartPlanGenerationStatus, reason: PlanGenerationFailureReason? = nil) {
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
            trackOutcome { Analytics.trackPlanGenerationFailed(durationMs: $0, reason: reason ?? .unknown) }
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
