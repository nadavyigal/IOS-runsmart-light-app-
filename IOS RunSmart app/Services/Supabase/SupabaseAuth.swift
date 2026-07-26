import Foundation
import CryptoKit
import AuthenticationServices
import Supabase

// MARK: - Nonce helpers (used by SignInView)

enum AppleSignInHelper {
    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", UInt32($0)) }.joined()
    }
}

// MARK: - Email sign-in outcome

/// Creating an account can land in one of two places depending on a Supabase
/// project setting the app cannot read: with email confirmation off the server
/// returns a live session, with it on it returns a user and no session. Both are
/// success — only the next screen differs — so the app branches at runtime
/// rather than hard-coding an assumption about the project's configuration.
enum EmailSignUpOutcome: Equatable {
    case signedIn
    case confirmationRequired
}

// MARK: - Errors

enum AppleSignInError: LocalizedError {
    case invalidCredential
    case missingToken

    var errorDescription: String? {
        switch self {
        case .invalidCredential: "Apple sign-in returned an unexpected credential type."
        case .missingToken: "Could not read the identity token from Apple."
        }
    }
}

// MARK: - SupabaseSession: sign in with an already-obtained Apple token

extension SupabaseSession {
    func signInWithApple(
        idToken: String,
        nonce: String,
        appleDisplayName: String?,
        appleEmail: String?
    ) async throws {
        lastAuthError = nil
        rememberAppleProfile(displayName: appleDisplayName, email: appleEmail)
        print("[SupabaseSession] Apple sign-in: exchanging Apple identity token with Supabase")
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            print("[SupabaseSession] Apple sign-in succeeded uid=\(session.user.id)")
            await loadProfile(userID: session.user.id)
        } catch {
            lastAuthError = "Apple sign-in could not complete. Verify the Supabase Apple provider and native bundle ID audience."
            print("[SupabaseSession] Apple sign-in failed:", error)
            throw error
        }
    }
}

// MARK: - SupabaseSession: email + password

/// The second way into the app.
///
/// Sign in with Apple cannot complete on a device with no Apple Account signed
/// in: iOS shows its own "Sign in to your Apple Account" alert and, once it is
/// dismissed, hands back a bare `ASAuthorizationError` code 1000 with no
/// underlying error. Reproduced on a clean simulator 2026-07-26, emitting the
/// identical `sign_in_failed` signature (`error_code 1000`,
/// `has_underlying_error false`) seen on every failing production session.
/// Nothing the app does to the Apple request can change that outcome, so while
/// Apple sign-in was the only door, those users were permanently locked out.
///
/// Email is deliberately password-based rather than a one-time code or magic
/// link: both of those depend on the Supabase email template and redirect
/// configuration, whereas password auth is already live on this project (12
/// confirmed email identities predate this change) and needs no server-side
/// change to start working.
extension SupabaseSession {
    func signInWithEmail(email: String, password: String) async throws {
        lastAuthError = nil
        // Never log the address itself — this path runs on real user accounts.
        print("[SupabaseSession] Email sign-in: exchanging credentials with Supabase")
        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            print("[SupabaseSession] Email sign-in succeeded uid=\(session.user.id)")
            await loadProfile(userID: session.user.id)
        } catch {
            print("[SupabaseSession] Email sign-in failed:", type(of: error))
            throw error
        }
    }

    func signUpWithEmail(email: String, password: String) async throws -> EmailSignUpOutcome {
        lastAuthError = nil
        print("[SupabaseSession] Email sign-up: creating account")
        do {
            let response = try await supabase.auth.signUp(email: email, password: password)
            switch response {
            case .session(let session):
                print("[SupabaseSession] Email sign-up signed in uid=\(session.user.id)")
                await loadProfile(userID: session.user.id)
                return .signedIn
            case .user:
                print("[SupabaseSession] Email sign-up awaiting confirmation")
                return .confirmationRequired
            }
        } catch {
            print("[SupabaseSession] Email sign-up failed:", type(of: error))
            throw error
        }
    }
}
