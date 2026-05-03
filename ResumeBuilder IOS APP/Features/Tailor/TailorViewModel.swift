import Foundation
import Observation

@Observable
@MainActor
final class TailorViewModel {
    var resumeId = ""
    var jobDescriptionId = ""
    var isOptimizing = false
    var reviewId: String?
    var errorMessage: String?

    private let apiClient = APIClient()

    func optimize(token: String?) async {
        guard !resumeId.isEmpty, !jobDescriptionId.isEmpty else {
            errorMessage = "resumeId and jobDescriptionId are required."
            return
        }

        guard let token else {
            errorMessage = "Please sign in first."
            return
        }

        isOptimizing = true
        errorMessage = nil
        defer { isOptimizing = false }

        do {
            let payload: [String: Any] = [
                "resumeId": resumeId,
                "jobDescriptionId": jobDescriptionId,
            ]
            let response: TailorResponse = try await apiClient.postJSON(endpoint: .optimize, body: payload, token: token)
            reviewId = response.reviewId
            if response.reviewId == nil {
                errorMessage = response.error ?? "Optimization did not return review id."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
