import SwiftUI

struct ScoreView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: ScoreViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Score")
                        .font(.largeTitle.bold())

                    TextEditor(text: $viewModel.jobDescription)
                        .frame(minHeight: 180)
                        .padding(8)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                    Button {
                        Task { await viewModel.runScore(token: appState.session?.accessToken) }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Run ATS Score")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if let result = viewModel.result {
                        ScoreResultView(result: result)
                    }
                }
                .padding()
            }
            .navigationTitle("Score")
        }
    }
}
