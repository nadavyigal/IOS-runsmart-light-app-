import SwiftUI

struct TailorView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: TailorViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tailor")
                        .font(.largeTitle.bold())

                    TextField("Resume ID", text: $viewModel.resumeId)
                        .textFieldStyle(.roundedBorder)

                    TextField("Job Description ID", text: $viewModel.jobDescriptionId)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        Task { await viewModel.optimize(token: appState.session?.accessToken) }
                    } label: {
                        Text("Optimize")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if viewModel.isOptimizing {
                        OptimizingView()
                    }

                    if let reviewId = viewModel.reviewId {
                        Text("Review ID: \(reviewId)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        DiffReviewView()
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Tailor")
        }
    }
}
