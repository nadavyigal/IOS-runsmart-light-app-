import Foundation

/// Session-scoped state machine behind the `sign_in_wall_*` events (activation
/// cliff plan, S1).
///
/// The wall is the first screen every unauthenticated user sees
/// (`RunSmartLiteAppShell.swift:184`) and it fired no event at all, so
/// "bounced in 2 seconds" and "stared at it for five minutes" were
/// indistinguishable in PostHog — 22 of 23 organic App Store users produced
/// zero events after app open and we could not say why.
///
/// Semantics are deliberately strict so the viewed -> tapped -> completed drop
/// is attributable rather than merely suggestive:
///
/// - `viewed` fires at most once per app session (this type is a process-lifetime
///   singleton in production; a fresh launch is a fresh session).
/// - `abandoned` fires only when the app backgrounds after at least
///   ``abandonThresholdSeconds`` on the wall with no sign-in attempt, and at
///   most once per session.
/// - A tap permanently disarms `abandoned`: returning to the foreground and
///   then attempting sign-in must not retro-emit an abandonment.
///
/// `now` is injectable so the dwell-threshold branches are testable without
/// sleeping.
final class SignInWallTracker {
    static let shared = SignInWallTracker()

    /// Explicit screen name. SwiftUI `$screen` autocapture emits the same generic
    /// `UIHostingController<...>` string for every screen, so it cannot identify
    /// the wall.
    static let screenName = "sign_in_wall"

    /// A user who backgrounds the app faster than this never really read the
    /// screen; counting them as "abandoned" would inflate the signal we are
    /// trying to measure.
    static let abandonThresholdSeconds: TimeInterval = 5

    private let now: () -> Date
    private var viewedAt: Date?
    private var didAttemptSignIn = false
    private var didTrackAbandon = false

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func wallAppeared() {
        guard viewedAt == nil else { return }
        viewedAt = now()
        Analytics.trackSignInWallViewed()
    }

    func signInTapped() {
        didAttemptSignIn = true
        Analytics.trackSignInWallTapped()
    }

    func appDidEnterBackground() {
        guard let viewedAt, !didAttemptSignIn, !didTrackAbandon else { return }
        let dwell = now().timeIntervalSince(viewedAt)
        guard dwell >= Self.abandonThresholdSeconds else { return }
        didTrackAbandon = true
        Analytics.trackSignInWallAbandoned(dwellSeconds: Int(dwell.rounded()))
    }
}
