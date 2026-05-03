import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    var session: AuthSession?
    var pendingSharedJobURL: URL?
    var creditsBalance: Int = 0

    let apiClient = APIClient()

    var isAuthenticated: Bool {
        session != nil
    }

    func bootstrap() {
        session = AuthService.shared.restoreSession()
    }

    func handleIncomingURL(_ url: URL) {
        if let sharedURL = DeepLinkRouter.parseSharedJobURL(from: url) {
            pendingSharedJobURL = sharedURL
        }
    }

    func signOut() {
        AuthService.shared.clearSession()
        session = nil
        creditsBalance = 0
    }

    func refreshCredits() async {
        guard let token = session?.accessToken else { return }

        do {
            let response: CreditsResponse = try await apiClient.get(endpoint: .credits, token: token)
            creditsBalance = response.balance
        } catch {
            // Keep prior balance on transient failures.
        }
    }
}
