import Foundation
import Testing
@testable import ResumeBuilder_IOS_APP

struct ResumeOptimizationServiceSwiftTestingTests {
    @Test("ImproveViewModel optimize succeeds with injected service")
    @MainActor
    func improveViewModelOptimizeSuccess() async throws {
        let viewModel = ImproveViewModel(
            resumeId: "resume_1",
            jobDescriptionId: "job_1",
            jobDescription: "iOS Engineer",
            analysisService: MockResumeAnalysisService(),
            optimizationService: MockResumeOptimizationService()
        )

        let result = await viewModel.optimize(token: "token")
        #expect(result?.optimizationId == "mock-opt-001")
        #expect(result?.sections.count == 3)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("ImproveViewModel optimize surfaces service failures")
    @MainActor
    func improveViewModelOptimizeFailure() async {
        let viewModel = ImproveViewModel(
            resumeId: "resume_1",
            jobDescriptionId: "job_1",
            jobDescription: "iOS Engineer",
            analysisService: MockResumeAnalysisService(),
            optimizationService: FailingResumeOptimizationService()
        )

        let result = await viewModel.optimize(token: "token")
        #expect(result == nil)
        #expect(viewModel.errorMessage == "Network unavailable")
    }

    @Test("ImproveViewModel optimize surfaces invalid data errors")
    @MainActor
    func improveViewModelOptimizeInvalidData() async {
        let viewModel = ImproveViewModel(
            resumeId: "resume_1",
            jobDescriptionId: "job_1",
            jobDescription: "iOS Engineer",
            analysisService: MockResumeAnalysisService(),
            optimizationService: InvalidDataResumeOptimizationService()
        )

        let result = await viewModel.optimize(token: "token")
        #expect(result == nil)
        #expect(viewModel.errorMessage == "Server returned invalid optimization payload.")
    }

    @Test("ImproveViewModel optimize surfaces decode errors gracefully")
    @MainActor
    func improveViewModelOptimizeDecodeError() async {
        let viewModel = ImproveViewModel(
            resumeId: "resume_1",
            jobDescriptionId: "job_1",
            jobDescription: "iOS Engineer",
            analysisService: MockResumeAnalysisService(),
            optimizationService: DecodeFailureResumeOptimizationService()
        )

        let result = await viewModel.optimize(token: "token")
        #expect(result == nil)
        #expect(viewModel.errorMessage == "We couldn't parse the optimization response. Please try again.")
    }

    @Test("OptimizeResponse decodes nested optimized resume payload")
    @MainActor
    func optimizeResponseDecoding() throws {
        let json = """
        {
          "data": {
            "success": true,
            "optimization_id": "opt_nested",
            "optimized_resume": [
              {
                "id": "summary",
                "type": "summary",
                "content": "Updated summary",
                "status": "optimized"
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(OptimizeResponse.self, from: json)
        #expect(response.optimizationId == "opt_nested")
        #expect(response.sections?.first?.type == .summary)
        #expect(response.sections?.first?.body == "Updated summary")
    }
}

private struct FailingResumeOptimizationService: ResumeOptimizationServiceProtocol {
    func optimize(resumeId: String, jobDescriptionId: String, token: String) async throws -> OptimizeResponse {
        throw ResumeOptimizationFailure.network
    }

    func refineSection(_ request: RefineSectionRequest, token: String) async throws -> RefineSectionResponse {
        throw ResumeOptimizationFailure.network
    }

    func applySectionRefine(_ request: RefineSectionApplyRequest, token: String) async throws -> Bool {
        throw ResumeOptimizationFailure.network
    }
}

private enum ResumeOptimizationFailure: LocalizedError {
    case network

    var errorDescription: String? { "Network unavailable" }
}

private struct InvalidDataResumeOptimizationService: ResumeOptimizationServiceProtocol {
    func optimize(resumeId: String, jobDescriptionId: String, token: String) async throws -> OptimizeResponse {
        throw ResumeOptimizationError.invalidResponse("Server returned invalid optimization payload.")
    }

    func refineSection(_ request: RefineSectionRequest, token: String) async throws -> RefineSectionResponse {
        throw ResumeOptimizationError.invalidResponse("Server returned invalid optimization payload.")
    }

    func applySectionRefine(_ request: RefineSectionApplyRequest, token: String) async throws -> Bool {
        throw ResumeOptimizationError.invalidResponse("Server returned invalid optimization payload.")
    }
}

private struct DecodeFailureResumeOptimizationService: ResumeOptimizationServiceProtocol {
    func optimize(resumeId: String, jobDescriptionId: String, token: String) async throws -> OptimizeResponse {
        throw ResumeOptimizationError.invalidResponse("We couldn't parse the optimization response. Please try again.")
    }

    func refineSection(_ request: RefineSectionRequest, token: String) async throws -> RefineSectionResponse {
        throw ResumeOptimizationError.invalidResponse("We couldn't parse the optimization response. Please try again.")
    }

    func applySectionRefine(_ request: RefineSectionApplyRequest, token: String) async throws -> Bool {
        throw ResumeOptimizationError.invalidResponse("We couldn't parse the optimization response. Please try again.")
    }
}
