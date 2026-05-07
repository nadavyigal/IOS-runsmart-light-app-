import SwiftUI
import UniformTypeIdentifiers

struct TailorView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: TailorViewModel
    @State private var isImporterPresented = false
    @State private var navigateTo: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // ── Hero header ───────────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tailor Resume")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Upload your resume and a job link. AI rewrites it to beat ATS filters.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        // ── Upload PDF ────────────────────────────────────────
                        Button {
                            isImporterPresented = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.body.weight(.semibold))
                                Text(viewModel.selectedResumeName ?? "Choose Resume PDF")
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(14)
                            .foregroundStyle(viewModel.selectedResumeName != nil ? Theme.accent : Theme.textSecondary)
                            .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous)
                                    .stroke(
                                        viewModel.selectedResumeName != nil ? Theme.accent.opacity(0.6) : Theme.textTertiary,
                                        lineWidth: 1
                                    )
                            )
                        }

                        // ── Job URL ───────────────────────────────────────────
                        TextField("LinkedIn or job post URL", text: $viewModel.jobDescriptionURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(14)
                            .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous)
                                    .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
                            )
                            .foregroundStyle(Theme.textPrimary)
                            .tint(Theme.accent)

                        // ── Job description paste ─────────────────────────────
                        ZStack(alignment: .topLeading) {
                            Theme.bgCard
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous)
                                        .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
                                )

                            if viewModel.jobDescription.isEmpty {
                                Text("Optional: paste job description instead")
                                    .foregroundStyle(Theme.textTertiary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 20)
                            }

                            TextEditor(text: $viewModel.jobDescription)
                                .scrollContentBackground(.hidden)
                                .background(.clear)
                                .frame(minHeight: 130)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 12)
                                .foregroundStyle(Theme.textPrimary)
                                .tint(Theme.accent)
                        }
                        .frame(minHeight: 130)

                        // ── Hidden navigation destination ─────────────────────
                        NavigationLink(value: navigateTo) { EmptyView() }
                            .hidden()
                            .navigationDestination(for: String.self) { reviewId in
                                OptimizedResumeView(reviewId: reviewId)
                            }

                        // ── Optimize button ───────────────────────────────────
                        Button {
                            Task {
                                await viewModel.optimize(appState: appState)
                                if let reviewId = viewModel.reviewId {
                                    navigateTo = reviewId
                                }
                            }
                        } label: {
                            Group {
                                if viewModel.isOptimizing {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(appState.isAuthenticated ? "Optimize Resume" : "Sign in to Optimize")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(.white)
                            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton, style: .continuous))
                        }
                        .disabled(viewModel.isOptimizing)

                        // ── Optimizing indicator ──────────────────────────────
                        if viewModel.isOptimizing {
                            OptimizingView()
                        }

                        // ── Error ─────────────────────────────────────────────
                        if let errorMessage = viewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Tailor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                viewModel.useSharedJobURLIfNeeded(from: appState)
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    viewModel.selectedResumeURL = url
                    viewModel.selectedResumeName = url.lastPathComponent
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
