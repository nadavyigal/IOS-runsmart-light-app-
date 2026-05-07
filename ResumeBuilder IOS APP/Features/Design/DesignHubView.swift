import SwiftUI
import Observation

/// Design tab entry point — shows recent optimizations as cards.
/// Tapping one opens RedesignView for that optimization.
struct DesignHubView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = DesignHubViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgPrimary.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView().tint(Theme.accent)
                } else if viewModel.optimizations.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Choose an optimization to design")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 20)

                            ForEach(viewModel.optimizations) { item in
                                NavigationLink {
                                    RedesignView(
                                        optimizationId: item.id,
                                        snapshot: viewModel.snapshot(for: item)
                                    )
                                } label: {
                                    optimizationCard(item)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .navigationTitle("Design")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await viewModel.load(token: appState.session?.accessToken) }
            .refreshable { await viewModel.load(token: appState.session?.accessToken) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "paintbrush")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textTertiary)
            Text("No optimizations yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Go to Improve tab to create your first optimized resume, then design it here.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func optimizationCard(_ item: OptimizationItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "doc.richtext.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.jobDescription?.title ?? item.jobTitle ?? "Optimized Resume")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let company = item.jobDescription?.company ?? item.company {
                    Text(company)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                if let score = item.matchScore {
                    Text("ATS \(score)%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accentCyan)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .stroke(Theme.accent.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class DesignHubViewModel {
    var optimizations: [OptimizationItem] = []
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
            optimizations = response.resolvedOptimizations
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func snapshot(for item: OptimizationItem) -> ResumeSnapshot {
        ResumeSnapshot(
            id: item.id,
            title: item.jobDescription?.title ?? item.jobTitle ?? "Resume",
            subtitle: item.jobDescription?.company ?? item.company ?? "",
            matchScore: item.matchScore,
            json: item.rewriteData
        )
    }
}
