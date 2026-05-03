import Foundation
import Observation

@Observable
@MainActor
final class ApplicationsViewModel {
    var applications: [ApplicationItem] = []
    var isLoading = false
    var errorMessage: String?

    private let apiClient = APIClient()

    func load(token: String?) async {
        guard let token else {
            errorMessage = "Please sign in first."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            applications = try await apiClient.get(endpoint: .applications, token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
