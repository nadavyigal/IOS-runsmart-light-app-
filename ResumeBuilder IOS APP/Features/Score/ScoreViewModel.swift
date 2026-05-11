import Foundation
import Observation

@Observable
@MainActor
final class ScoreViewModel {
    var jobDescription = ""
    var jobDescriptionURL = ""
    var selectedResumeURL: URL?
    var selectedResumeName: String?
    var isLoading = false
    var result: ATSScoreResult?
    var errorMessage: String?

    private let apiClient = APIClient()

    func runScore(appState: AppState) async {
        guard let selectedResumeURL else {
            errorMessage = "Choose a PDF resume first."
            return
        }

        let trimmedDescription = jobDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = jobDescriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty || !trimmedURL.isEmpty else {
            errorMessage = "Paste a job description or add a job link."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await apiClient.runPublicATSCheck(
                resumeURL: selectedResumeURL,
                jobDescription: trimmedDescription.isEmpty ? nil : trimmedDescription,
                jobDescriptionURL: trimmedURL.isEmpty ? nil : trimmedURL,
                sessionId: appState.anonymousATSSessionId
            )
            result = response
            appState.storeAnonymousATSSessionId(response.sessionId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func useSharedJobURLIfNeeded(from appState: AppState) {
        guard jobDescriptionURL.isEmpty, let sharedURL = appState.pendingSharedJobURL else { return }
        jobDescriptionURL = sharedURL.absoluteString
        appState.clearPendingSharedJobURL()
    }
}
