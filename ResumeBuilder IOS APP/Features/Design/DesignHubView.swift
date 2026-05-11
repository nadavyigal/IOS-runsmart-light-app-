import SwiftUI
import Observation

struct DesignHubView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = DesignHubViewModel()
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgPrimary.ignoresSafeArea()

                RadialGradient(
                    colors: [Theme.accentCyan.opacity(0.09), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 380
                )
                .ignoresSafeArea()

                if viewModel.isLoading {
                    loadingView
                } else if viewModel.optimizations.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            pageHeader
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 12)

                            LazyVStack(spacing: 14) {
                                ForEach(Array(viewModel.optimizations.enumerated()), id: \.element.id) { index, item in
                                    NavigationLink {
                                        RedesignView(
                                            optimizationId: item.id,
                                            snapshot: viewModel.snapshot(for: item)
                                        )
                                    } label: {
                                        optimizationCard(item, index: index)
                                    }
                                    .buttonStyle(.plain)
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : CGFloat(20 + index * 8))
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 100)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .refreshable { await viewModel.load(token: appState.session?.accessToken) }
                }
            }
            .navigationBarHidden(true)
            .task {
                await viewModel.load(token: appState.session?.accessToken)
                withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            }
        }
    }

    // MARK: - Subviews

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "paintbrush.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accentCyan)
                Text("TEMPLATES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.accentCyan)
                    .kerning(1.2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.accentCyan.opacity(0.12), in: Capsule())

            Text("Design")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.accentCyan, Theme.accentBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Apply a professional template to your optimized resume.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
        }
    }

    private func optimizationCard(_ item: OptimizationHistoryItem, index: Int) -> some View {
        HStack(spacing: 0) {
            // Colored left accent bar
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(cardAccentGradient(for: index))
                .frame(width: 4)
                .padding(.vertical, 14)

            HStack(spacing: 14) {
                // Icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(cardAccentGradient(for: index).opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(cardAccentColor(for: index))
                }

                // Text content
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.jobTitle ?? "Optimized Resume")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    if let company = item.company {
                        HStack(spacing: 4) {
                            Image(systemName: "building.2")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textTertiary)
                            Text(company)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .lineLimit(1)
                    }

                    ATSScorePill(score: item.matchScorePercent)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.trailing, 6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Theme.accentCyan.opacity(0.08))
                    .frame(width: 90, height: 90)
                Image(systemName: "paintbrush.pointed.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.accentCyan, Theme.accentBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("No designs yet")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Tailor a resume first, then come here to apply a professional template.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 40)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Theme.accentCyan)
            Text("Loading designs…")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func cardAccentGradient(for index: Int) -> LinearGradient {
        let gradients: [LinearGradient] = [
            LinearGradient(colors: [Theme.accent, Theme.accentBlue], startPoint: .top, endPoint: .bottom),
            LinearGradient(colors: [Theme.accentBlue, Theme.accentCyan], startPoint: .top, endPoint: .bottom),
            LinearGradient(colors: [Theme.accentCyan, Theme.accent], startPoint: .top, endPoint: .bottom),
        ]
        return gradients[index % gradients.count]
    }

    private func cardAccentColor(for index: Int) -> Color {
        let colors = [Theme.accent, Theme.accentBlue, Theme.accentCyan]
        return colors[index % colors.count]
    }
}

// MARK: - ATS Score Pill

struct ATSScorePill: View {
    let score: Int

    private var color: Color {
        if score >= 80 { return Theme.accentCyan }
        if score >= 60 { return Theme.accentBlue }
        return Theme.accent
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("ATS \(score)%")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class DesignHubViewModel {
    var optimizations: [OptimizationHistoryItem] = []
    var isLoading = false
    var errorMessage: String?

    private let apiClient = APIClient()

    func load(token: String?) async {
        guard let token else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let response: OptimizationHistoryResponse = try await apiClient.get(
                endpoint: .optimizations,
                token: token
            )
            optimizations = response.allItems
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func snapshot(for item: OptimizationHistoryItem) -> ResumeSnapshot {
        ResumeSnapshot(
            id: item.id,
            title: item.jobTitle ?? "Resume",
            subtitle: item.company ?? "",
            matchScore: item.matchScorePercent,
            json: nil
        )
    }
}
