import Foundation
import Observation

@Observable
@MainActor
final class OnboardingViewModel {
    var email = ""
    var password = ""
    var isLoading = false
    var errorMessage: String?

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func signInWithEmail() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let session = try await AuthService.shared.signInWithEmail(email: email, password: password)
            appState.session = session
            await appState.refreshCredits()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInWithApple() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let session = try await AuthService.shared.signInWithApple()
            appState.session = session
            await appState.refreshCredits()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
