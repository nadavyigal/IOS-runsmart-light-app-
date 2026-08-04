import Combine
import Foundation
import Supabase

/// Drives the email sign-in sheet.
///
/// The flow lives here rather than in the view so it can be tested without a
/// running Supabase or a rendered SwiftUI hierarchy — the previous sign-in
/// surface had no testable seam at all, which is part of why a total lockout
/// went unnoticed from inside the codebase for weeks.
@MainActor
final class EmailSignInModel: ObservableObject {
    enum Mode: String, Equatable, CaseIterable {
        case signIn
        case createAccount

        var title: String {
            switch self {
            case .signIn: "Sign in"
            case .createAccount: "Create account"
            }
        }

        /// Sent with the analytics events so the two branches stay separable.
        var analyticsValue: String { rawValue }
    }

    enum Phase: Equatable {
        case editing
        case submitting
        /// Supabase accepted the account but requires an emailed confirmation
        /// before the user can sign in.
        case confirmationRequired
    }

    /// Injection seam. Production wires these to `SupabaseSession`; tests pass
    /// closures so every branch below is reachable without a network.
    struct Gateway {
        var signIn: (_ email: String, _ password: String) async throws -> Void
        var signUp: (_ email: String, _ password: String) async throws -> EmailSignUpOutcome

        init(
            signIn: @escaping (String, String) async throws -> Void,
            signUp: @escaping (String, String) async throws -> EmailSignUpOutcome
        ) {
            self.signIn = signIn
            self.signUp = signUp
        }
    }

    static let minimumPasswordLength = 8

    @Published var email = ""
    @Published var password = ""
    @Published var mode: Mode = .signIn
    @Published private(set) var phase: Phase = .editing
    @Published private(set) var errorMessage: String?

    private let gateway: Gateway

    init(gateway: Gateway) {
        self.gateway = gateway
    }

    /// Addresses are trimmed and lowercased before they leave the device.
    /// Supabase treats addresses case-insensitively, but a stray capital or a
    /// trailing space pasted from a password manager otherwise reads to the
    /// user as "wrong password" on an account that exists.
    var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isSubmitting: Bool { phase == .submitting }

    var canSubmit: Bool {
        phase != .submitting
            && Self.isValidEmail(normalizedEmail)
            && Self.isAcceptablePassword(password)
    }

    /// Deliberately permissive: the server is the authority on deliverability,
    /// and an over-strict client regex is itself a lockout. This only rejects
    /// input that cannot be an address at all.
    static func isValidEmail(_ candidate: String) -> Bool {
        let parts = candidate.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = parts[1]
        guard !local.isEmpty, !domain.isEmpty else { return false }
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        guard !candidate.contains(" ") else { return false }
        return true
    }

    static func isAcceptablePassword(_ candidate: String) -> Bool {
        candidate.count >= minimumPasswordLength
    }

    func switchMode(to newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        errorMessage = nil
        if phase == .confirmationRequired { phase = .editing }
    }

    func submit() async {
        guard canSubmit else { return }
        let address = normalizedEmail
        let secret = password
        let submittedMode = mode

        phase = .submitting
        errorMessage = nil

        do {
            switch submittedMode {
            case .signIn:
                try await gateway.signIn(address, secret)
                // On success the session flips `isAuthenticated` and the shell
                // swaps this whole surface out, so there is no success phase to
                // set here — doing so would fight the shell for the transition.
                phase = .editing
                Analytics.trackSignInCompleted(method: "email", mode: submittedMode.analyticsValue)
            case .createAccount:
                let outcome = try await gateway.signUp(address, secret)
                switch outcome {
                case .signedIn:
                    phase = .editing
                    Analytics.trackSignInCompleted(method: "email", mode: submittedMode.analyticsValue)
                case .confirmationRequired:
                    phase = .confirmationRequired
                    // The account exists but no session was issued, so this is
                    // neither a completion nor a failure. It emitted nothing at
                    // all until WP-67, which is why a successfully created
                    // account read in the funnel as a flat failure.
                    Analytics.trackSignInPendingConfirmation(
                        method: "email", mode: submittedMode.analyticsValue)
                }
            }
        } catch {
            phase = .editing
            errorMessage = Self.humanReadableError(for: error, mode: submittedMode)
            Analytics.trackSignInFailed(
                error: error, method: "email", mode: submittedMode.analyticsValue)
        }
    }

    /// Maps a failure to copy a first-time user can act on.
    ///
    /// Same guarantee the Apple path carries: never forward
    /// `NSError.localizedDescription`, because that puts strings like
    /// "com.apple…error 1000" or a raw Postgres message on screen. The
    /// wrong-mode cases matter most — a user who taps "Create account" on an
    /// address they already own, or "Sign in" on one they do not, is one
    /// sentence away from success and must be told which.
    static func humanReadableError(for error: Error, mode: Mode) -> String {
        if let authError = error as? AuthError {
            switch authError.errorCode {
            case .invalidCredentials:
                return "That email and password don't match an account. "
                     + "Check the password, or switch to Create account if you're new."
            case .userAlreadyExists, .emailExists:
                return "You already have an account with that email. Switch to Sign in."
            case .emailNotConfirmed:
                return "Check your email and tap the confirmation link, then sign in."
            case .weakPassword:
                return "Pick a password of at least \(minimumPasswordLength) characters."
            case .overRequestRateLimit, .requestTimeout:
                return "Too many attempts just now. Wait a minute, then try again."
            case .overEmailSendRateLimit:
                return "Too many confirmation emails just now. Wait a few minutes, then try again."
            case .emailAddressNotAuthorized
                where mode == .createAccount:
                // Supabase accepted the account but the mail provider refused
                // the address, so the signup is rolled back and retrying the
                // same address changes nothing.
                //
                // This project sends through Resend on a verified
                // `runsmart-ai.com` domain (confirmed delivering 2026-07-26),
                // so this is not the normal path — it is what a user sees if
                // the provider rejects their address, the domain falls out of
                // verification, or the sending quota is exhausted. Sending them
                // back to "try again" would be the same dead end Sign in with
                // Apple already created, so name the real state instead.
                return "We couldn't send the confirmation email, so no account was created. "
                     + "This is on our side — please try Sign in with Apple, or contact support."
            case .unexpectedFailure
                where mode == .createAccount
                    && authError.message.localizedCaseInsensitiveContains("confirmation email"):
                // GoTrue can wrap the same delivery failure in a generic 500.
                // Match both the create-account context and the server message;
                // `unexpected_failure` also represents unrelated backend faults
                // and must not be mislabeled during ordinary sign-in.
                return "We couldn't send the confirmation email, so no account was created. "
                     + "This is on our side — please try Sign in with Apple, or contact support."
            case .signupDisabled:
                return "Email sign-up isn't available right now. Please try Sign in with Apple."
            case .emailProviderDisabled:
                return mode == .createAccount
                    ? "Email sign-up isn't available right now. Please try Sign in with Apple."
                    : "Email sign-in isn't available right now. Please try Sign in with Apple."
            default:
                break
            }
        }

        if (error as NSError).domain == NSURLErrorDomain {
            return "Couldn't reach RunSmart. Check your connection, then try again."
        }

        switch mode {
        case .signIn:
            return "Sign-in didn't finish and nothing was changed. Please try again."
        case .createAccount:
            return "Account creation didn't finish and nothing was created. Please try again."
        }
    }
}
