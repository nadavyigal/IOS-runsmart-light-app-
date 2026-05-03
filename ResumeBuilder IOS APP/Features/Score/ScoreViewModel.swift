import Foundation
import Observation

@Observable
@MainActor
final class ScoreViewModel {
    var jobDescription = ""
    var isLoading = false
    var result: ATSScoreResult?
    var errorMessage: String?

    private let apiClient = APIClient()

    func runScore(token: String?) async {
        guard !jobDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Job description is required."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let token {
                let payload: [String: Any] = [
                    "resume_original": jobDescription,
                    "resume_optimized": jobDescription,
                    "job_description": jobDescription,
                ]
                result = try await apiClient.postJSON(endpoint: .atsScore, body: payload, token: token)
            } else {
                errorMessage = "Public scoring requires resume upload flow from onboarding."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
