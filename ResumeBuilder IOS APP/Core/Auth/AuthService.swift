import Foundation

enum AuthServiceError: Error, LocalizedError {
    case invalidResponse
    case missingSupabaseKey
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid auth response."
        case .missingSupabaseKey:
            return "SUPABASE_ANON_KEY is missing in Info.plist."
        case .serverError(let message):
            return message
        }
    }
}

final class AuthService {
    static let shared = AuthService()

    private let keychain = KeychainStore.shared
    private let service = "com.nadavyigal.resumebuilder.auth"
    private let account = "supabase_session"

    private init() {}

    func restoreSession() -> AuthSession? {
        guard let data = keychain.read(service: service, account: account) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func clearSession() {
        keychain.remove(service: service, account: account)
    }

    func signInWithEmail(email: String, password: String) async throws -> AuthSession {
        guard !BackendConfig.supabaseAnonKey.isEmpty else {
            throw AuthServiceError.missingSupabaseKey
        }

        let url = BackendConfig.supabaseURL
            .appendingPathComponent("auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BackendConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        let payload = [
            "email": email,
            "password": password,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? "Authentication failed"
            throw AuthServiceError.serverError(text)
        }

        struct SupabaseAuthResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let user: User

            struct User: Decodable {
                let id: String
                let email: String?
            }
        }

        let decoded = try JSONDecoder().decode(SupabaseAuthResponse.self, from: data)
        let session = AuthSession(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            userId: decoded.user.id,
            email: decoded.user.email
        )

        if let encoded = try? JSONEncoder().encode(session) {
            keychain.save(encoded, service: service, account: account)
        }

        return session
    }

    func signInWithApple() async throws -> AuthSession {
        throw AuthServiceError.serverError("Sign in with Apple flow is scaffolded and should be wired with Supabase OAuth config.")
    }
}
