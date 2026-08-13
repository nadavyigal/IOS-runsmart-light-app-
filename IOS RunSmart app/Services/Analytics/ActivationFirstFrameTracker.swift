/// The first resolved product surface rendered after launch/session loading.
///
/// The loading splash is deliberately not a case: if a launch never resolves
/// beyond it, PostHog must show `app_launched` without this event. Counting the
/// splash would make a stuck launch look healthy and preserve WP-61a's blind
/// spot between launch and the sign-in wall.
enum ActivationFirstFrameScreen: String, Sendable {
    case signInWall = "sign_in_wall"
    case guestValue = "guest_value"
    case onboarding
    case mainApp = "main_app"

    static func resolved(
        isLaunchOverlayVisible: Bool,
        isLoading: Bool,
        isAuthenticated: Bool,
        hasCompletedOnboarding: Bool,
        isGuestJourneyActive: Bool = false
    ) -> Self? {
        guard !isLaunchOverlayVisible, !isLoading else { return nil }
        guard isAuthenticated else {
            return isGuestJourneyActive ? .guestValue : .signInWall
        }
        return hasCompletedOnboarding ? .mainApp : .onboarding
    }
}

/// Process-lifetime guard for the first resolved activation frame.
///
/// SwiftUI can rebuild or remount every route below. One app process still has
/// one first resolved frame, so later appearances must not change the launch's
/// attribution.
@MainActor
final class ActivationFirstFrameTracker {
    static let shared = ActivationFirstFrameTracker()

    private let signInWallTracker: SignInWallTracker
    private var didTrackFrame = false

    init(signInWallTracker: SignInWallTracker) {
        self.signInWallTracker = signInWallTracker
    }

    convenience init() {
        self.init(signInWallTracker: .shared)
    }

    func screenRendered(_ screen: ActivationFirstFrameScreen) {
        guard !didTrackFrame else { return }
        didTrackFrame = true
        Analytics.trackActivationFirstFrameRendered(screen: screen)
        if screen == .signInWall {
            signInWallTracker.wallReachedAfterLaunch()
        }
    }
}
