import XCTest
@testable import ResumeBuilder_IOS_APP

@MainActor
final class ImproveViewModelTests: XCTestCase {
    func testOptimizeReturnsErrorWhenTokenMissing() async {
        let viewModel = ImproveViewModel(
            resumeId: "resume_1",
            jobDescriptionId: "job_1",
            jobDescription: "iOS Engineer",
            analysisService: MockResumeAnalysisService(),
            optimizationService: MockResumeOptimizationService()
        )

        let result = await viewModel.optimize(token: nil)
        XCTAssertNil(result)
        XCTAssertEqual(viewModel.errorMessage, ResumeOptimizationError.missingToken.localizedDescription)
    }

    func testOptimizeReturnsOptimizationIdAndSections() async {
        let viewModel = ImproveViewModel(
            resumeId: "resume_1",
            jobDescriptionId: "job_1",
            jobDescription: "iOS Engineer",
            analysisService: MockResumeAnalysisService(),
            optimizationService: MockResumeOptimizationService()
        )

        let result = await viewModel.optimize(token: "token")
        XCTAssertEqual(result.flatMap(\.optimizationId), "mock-opt-001")
        XCTAssertEqual(result?.sections.count, 3)
    }
}
