import SwiftUI

struct OnboardingView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Welcome to ResumeBuilder") {
                    Text("Tailor your resume to any job in 60 seconds.")
                        .foregroundStyle(.secondary)
                }

                Section("Sign in") {
                    TextField("Email", text: $viewModel.email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)

                    SecureField("Password", text: $viewModel.password)

                    Button {
                        Task { await viewModel.signInWithEmail() }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Continue")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Section {
                    Button("Sign in with Apple") {
                        Task { await viewModel.signInWithApple() }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                ImportResumeView()
            }
            .navigationTitle("Get Started")
        }
    }
}
