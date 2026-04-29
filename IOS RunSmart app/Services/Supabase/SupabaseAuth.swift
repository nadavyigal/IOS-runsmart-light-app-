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
        return hash.map { String(format: "%02x", $0) }.joined()
    }
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
    func signInWithApple(idToken: String, nonce: String) async throws {
        _ = try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
    }
}
