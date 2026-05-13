import SwiftUI
import UniformTypeIdentifiers

struct TailorView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: TailorViewModel
    @State private var isImporterPresented = false
    @State private var navigateTo: String?
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgPrimary.ignoresSafeArea()

                // Warm violet glow behind header
                RadialGradient(
                    colors: [Theme.accent.opacity(0.14), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 400
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        // ── Page header ──────────────────────────────────────
                        pageHeader
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)

                        // ── Step cards ───────────────────────────────────────
                        VStack(spacing: 12) {
                            stepCard(
                                step: 1,
                                title: "Upload Resume",
                                subtitle: viewModel.selectedResumeName ?? "PDF, up to 5 MB",
                                icon: "doc.fill",
                                isFilled: viewModel.selectedResumeName != nil,
                                action: { isImporterPresented = true }
                            )
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 16)

                            stepConnector(filled: viewModel.selectedResumeName != nil)

                            jobInputCard
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)

                            stepConnector(filled: !viewModel.jobDescriptionURL.isEmpty || !viewModel.jobDescription.isEmpty)

                            optimizeCard
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 24)
                        }

                        // ── Processing state ─────────────────────────────────
                        if viewModel.isOptimizing {
                            OptimizingView()
                                .transition(.scale.combined(with: .opacity))
                        }

                        // ── Error ────────────────────────────────────────────
                        if let error = viewModel.errorMessage {
                            errorBanner(error)
                        }

                        NavigationLink(value: navigateTo) { EmptyView() }
                            .hidden()
                            .navigationDestination(for: String.self) { reviewId in
                                OptimizedResumeView(
                                    viewModel: OptimizedResumeViewModel(optimizationId: reviewId)
                                )
                            }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationBarHidden(true)
            .onAppear {
                viewModel.useSharedJobURLIfNeeded(from: appState)
                withAnimation(.easeOut(duration: 0.55)) { appeared = true }
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

    // MARK: - Subviews

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("AI POWERED")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .kerning(1.2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.accent.opacity(0.12), in: Capsule())

            Text("Tailor Resume")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accentBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("AI rewrites your resume to beat ATS filters for any job.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
        }
    }

    private func stepCard(
        step: Int,
        title: String,
        subtitle: String,
        icon: String,
        isFilled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isFilled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.bgPrimary))
                        .frame(width: 36, height: 36)
                    if isFilled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(step)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isFilled ? Theme.accentBlue : Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isFilled ? "pencil" : "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isFilled ? Theme.accentBlue : Theme.textTertiary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(isFilled ? Theme.accentBlue.opacity(0.15) : Theme.bgPrimary.opacity(0.5))
                    )
            }
            .padding(16)
            .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isFilled ? Theme.accent.opacity(0.4) : Color.white.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .shadow(color: isFilled ? Theme.accent.opacity(0.1) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isFilled)
    }

    private func stepConnector(filled: Bool) -> some View {
        HStack {
            Spacer().frame(width: 38)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: filled
                            ? [Theme.accent.opacity(0.6), Theme.accentBlue.opacity(0.3)]
                            : [Theme.textTertiary.opacity(0.2), Theme.textTertiary.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2, height: 20)
                .padding(.leading, 17)
            Spacer()
        }
    }

    private var jobInputCard: some View {
        let jobFilled = !viewModel.jobDescriptionURL.isEmpty || !viewModel.jobDescription.isEmpty

        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(jobFilled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.bgPrimary))
                        .frame(width: 36, height: 36)
                    if jobFilled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("2")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add Job")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("URL or paste description")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.horizontal, 16)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 18)
                    TextField("LinkedIn or job post URL", text: $viewModel.jobDescriptionURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .foregroundStyle(Theme.textPrimary)
                        .tint(Theme.accent)
                        .font(.subheadline)
                }
                .padding(12)
                .background(Theme.bgPrimary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            viewModel.jobDescriptionURL.isEmpty
                                ? Color.white.opacity(0.06)
                                : Theme.accentBlue.opacity(0.4),
                            lineWidth: 1
                        )
                )

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.bgPrimary.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    viewModel.jobDescription.isEmpty
                                        ? Color.white.opacity(0.06)
                                        : Theme.accent.opacity(0.3),
                                    lineWidth: 1
                                )
                        )

                    if viewModel.jobDescription.isEmpty {
                        Text("Or paste job description here")
                            .foregroundStyle(Theme.textTertiary)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $viewModel.jobDescription)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .frame(minHeight: 110)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .foregroundStyle(Theme.textPrimary)
                        .tint(Theme.accent)
                        .font(.subheadline)
                }
                .frame(minHeight: 110)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    jobFilled ? Theme.accent.opacity(0.4) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: jobFilled)
    }

    private var optimizeCard: some View {
        let canOptimize = viewModel.selectedResumeName != nil
            && (!viewModel.jobDescriptionURL.isEmpty || !viewModel.jobDescription.isEmpty)

        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(canOptimize ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.bgPrimary))
                        .frame(width: 36, height: 36)
                    Text("3")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canOptimize ? Color.white : Theme.textTertiary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Optimize")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("AI rewrites for this specific job")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Divider()
                .background(Color.white.opacity(0.06))
                .padding(.horizontal, 16)

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
                        HStack(spacing: 8) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 15, weight: .semibold))
                            Text(appState.isAuthenticated ? "Optimize Resume" : "Sign in to Optimize")
                                .fontWeight(.bold)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(canOptimize ? Color.white : Theme.textTertiary)
                .background(
                    canOptimize && !viewModel.isOptimizing
                        ? AnyShapeStyle(Theme.brandGradient)
                        : AnyShapeStyle(Theme.bgPrimary.opacity(0.5)),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .shadow(
                    color: canOptimize && !viewModel.isOptimizing ? Theme.accent.opacity(0.35) : .clear,
                    radius: 10, y: 5
                )
            }
            .disabled(!canOptimize || viewModel.isOptimizing)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .animation(.easeInOut(duration: 0.2), value: canOptimize)
        }
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    canOptimize ? Theme.accent.opacity(0.4) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: canOptimize)
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
