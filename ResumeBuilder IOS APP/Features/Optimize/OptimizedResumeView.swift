import SwiftUI

struct OptimizedResumeView: View {
    @Environment(AppState.self) private var appState
    let reviewId: String
    @State private var viewModel = OptimizedResumeViewModel()
    @State private var navigateToRedesign = false
    @State private var showSaveSuccess = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bgPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    contentSections
                    Spacer().frame(height: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.basedOnSize)

            bottomBar
        }
        .navigationTitle("Optimized Resume")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await viewModel.load(reviewId: reviewId, token: appState.session?.accessToken)
        }
        .navigationDestination(isPresented: $navigateToRedesign) {
            if let optimizationId = viewModel.appliedOptimizationId {
                RedesignView(
                    optimizationId: optimizationId,
                    snapshot: viewModel.resumeSnapshot
                )
            }
        }
        .overlay {
            if showSaveSuccess {
                savedToast
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: showSaveSuccess)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.review?.jobDescription?.title ?? "Optimized Resume")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    if let company = viewModel.review?.jobDescription?.company {
                        Text(company)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                if let score = viewModel.atsScore {
                    atsScoreBadge(score)
                }
            }

            if viewModel.isLoading {
                HStack { Spacer(); ProgressView().tint(Theme.accent); Spacer() }
                    .padding(.vertical, 24)
            }

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func atsScoreBadge(_ score: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accentBlue)
            Text("AI Score")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.accentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .stroke(Theme.accentBlue.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Section Cards

    @ViewBuilder
    private var contentSections: some View {
        ForEach(viewModel.sections) { section in
            sectionCard(section)
        }
    }

    private func sectionCard(_ section: OptimizedResumeViewModel.OptimizedSection) -> some View {
        let isExpanded = viewModel.expandedSectionIds.contains(section.id)
        let visibleLines = isExpanded ? section.lines : Array(section.lines.prefix(3))

        return VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                viewModel.toggleExpanded(section.id)
            } label: {
                HStack(spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    improvementBadge(section.badge)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Divider()
                .background(Theme.accent.opacity(0.15))

            // Bullet lines
            VStack(alignment: .leading, spacing: 10) {
                ForEach(visibleLines) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(line.isImproved ? Theme.accentCyan : Theme.textTertiary)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(line.text)
                            .font(.subheadline)
                            .foregroundStyle(line.isImproved ? Theme.textPrimary : Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }

                if section.lines.count > 3 {
                    Button {
                        viewModel.toggleExpanded(section.id)
                    } label: {
                        Text(isExpanded ? "Show less" : "+ \(section.lines.count - 3) more")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .stroke(Theme.accent.opacity(0.12), lineWidth: 1)
        )
    }

    private func improvementBadge(_ badge: OptimizedResumeViewModel.ImprovementBadge) -> some View {
        let color: Color = switch badge {
        case .improved:  Theme.accentCyan
        case .ats:       Theme.accentBlue
        case .optimized: Theme.accent
        }
        return Label(badge.rawValue, systemImage: badge.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().background(Theme.accent.opacity(0.2))
            HStack(spacing: 12) {
                Button {
                    navigateToRedesign = viewModel.appliedOptimizationId != nil
                    if viewModel.appliedOptimizationId == nil {
                        Task { await applyAndNavigate() }
                    }
                } label: {
                    Label("Preview PDF", systemImage: "doc.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .foregroundStyle(Theme.accent)
                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusButton, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusButton, style: .continuous)
                                .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                        )
                }

                Button {
                    Task { await saveChanges() }
                } label: {
                    Group {
                        if viewModel.isApplying {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save Changes")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(.white)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton, style: .continuous))
                }
                .disabled(viewModel.isApplying)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private var savedToast: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accentCyan)
                Text("Changes saved!")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.bgCard, in: Capsule())
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .padding(.top, 60)
            Spacer()
        }
    }

    // MARK: - Actions

    private func saveChanges() async {
        await viewModel.applyAll(token: appState.session?.accessToken)
        if viewModel.appliedOptimizationId != nil {
            withAnimation { showSaveSuccess = true }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showSaveSuccess = false }
        }
    }

    private func applyAndNavigate() async {
        await viewModel.applyAll(token: appState.session?.accessToken)
        if viewModel.appliedOptimizationId != nil {
            navigateToRedesign = true
        }
    }
}
