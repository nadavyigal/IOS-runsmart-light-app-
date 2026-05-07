import SwiftUI
import Observation

struct DiffReviewView: View {
    @Environment(AppState.self) private var appState
    let reviewId: String
    @State private var viewModel = DiffReviewViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading review…").tint(Theme.accent)
                    Spacer()
                }
                .padding(.vertical, 24)
            }

            if let review = viewModel.review {
                // ── Header ────────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    Text(review.jobDescription?.title ?? "Optimization Review")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text([review.jobDescription?.company, review.jobDescription?.sourceURL]
                        .compactMap { $0 }.joined(separator: " • "))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }

                // ── Score dial ────────────────────────────────────────────────
                if let score = viewModel.afterScore {
                    HStack {
                        Spacer()
                        ATSDial(score: score)
                            .frame(width: 100, height: 100)
                        Spacer()
                    }
                }

                // ── Change groups ─────────────────────────────────────────────
                ForEach(viewModel.changeGroups) { group in
                    BulletDiffRow(
                        original: group.original,
                        optimized: group.optimized,
                        onAccept: { viewModel.accept(group.id) },
                        onReject: { viewModel.reject(group.id) }
                    )
                }

                if viewModel.changeGroups.isEmpty {
                    ResumePreviewCard(snapshot: viewModel.resumeSnapshot)
                }

                // ── Apply button ──────────────────────────────────────────────
                Button {
                    Task { await viewModel.apply(token: appState.session?.accessToken) }
                } label: {
                    Group {
                        if viewModel.isApplying {
                            ProgressView().tint(.white)
                        } else {
                            Text("Apply Accepted Changes")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton, style: .continuous))
                    .opacity(viewModel.isApplying || viewModel.acceptedGroupIds.isEmpty ? 0.4 : 1.0)
                }
                .disabled(viewModel.isApplying || viewModel.acceptedGroupIds.isEmpty)
            }

            // ── Design link ───────────────────────────────────────────────────
            if let optimizationId = viewModel.appliedOptimizationId {
                NavigationLink {
                    RedesignView(
                        optimizationId: optimizationId,
                        snapshot: viewModel.resumeSnapshot
                    )
                } label: {
                    Label("Design Optimized Resume", systemImage: "paintbrush.fill")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundStyle(Theme.accent)
                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusButton, style: .continuous))
                }
            }

            // ── Error ─────────────────────────────────────────────────────────
            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .task(id: reviewId) {
            await viewModel.load(reviewId: reviewId, token: appState.session?.accessToken)
        }
    }
}

// MARK: - Supporting types

struct ReviewChangeGroup: Identifiable, Sendable {
    let id: String
    let original: String
    let optimized: String
}

// MARK: - ViewModel

@Observable
@MainActor
final class DiffReviewViewModel {
    var review: OptimizationReviewResponse?
    var changeGroups: [ReviewChangeGroup] = []
    var acceptedGroupIds: Set<String> = []
    var rejectedGroupIds: Set<String> = []
    var isLoading = false
    var isApplying = false
    var appliedOptimizationId: String?
    var errorMessage: String?

    private let apiClient = APIClient()
    private var reviewId: String?

    var afterScore: Int? {
        guard let object = review?.review.atsPreviewJSON?.objectValue else { return nil }
        return object["after"]?.intValue ?? object["optimized"]?.intValue
    }

    var resumeSnapshot: ResumeSnapshot {
        ResumeSnapshot(
            id: appliedOptimizationId ?? reviewId ?? UUID().uuidString,
            title: review?.jobDescription?.title ?? "Optimized Resume",
            subtitle: review?.jobDescription?.company ?? "Resume preview",
            matchScore: afterScore,
            json: review?.review.optimizedResumeJSON
        )
    }

    func load(reviewId: String, token: String?) async {
        guard let token else { errorMessage = "Please sign in first."; return }
        self.reviewId = reviewId
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: OptimizationReviewResponse = try await apiClient.get(endpoint: .optimizationReview(reviewId), token: token)
            review = response
            changeGroups = Self.extractChangeGroups(from: response.review.groupedChangesJSON)
            acceptedGroupIds = Set(changeGroups.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func accept(_ id: String) {
        rejectedGroupIds.remove(id)
        acceptedGroupIds.insert(id)
    }

    func reject(_ id: String) {
        acceptedGroupIds.remove(id)
        rejectedGroupIds.insert(id)
    }

    func apply(token: String?) async {
        guard let token, let reviewId else { errorMessage = "Please sign in first."; return }

        struct ApplyRequest: Encodable {
            let approvedGroupIds: [String]
        }

        isApplying = true
        errorMessage = nil
        defer { isApplying = false }

        do {
            let response: ApplyReviewResponse = try await apiClient.postCodable(
                endpoint: .applyOptimizationReview(reviewId),
                body: ApplyRequest(approvedGroupIds: Array(acceptedGroupIds)),
                token: token
            )
            appliedOptimizationId = response.optimizationId
            if appliedOptimizationId == nil {
                errorMessage = response.error ?? "Apply completed without an optimization id."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func extractChangeGroups(from json: JSONValue?) -> [ReviewChangeGroup] {
        guard let json else { return [] }
        let values: [JSONValue]
        if let array = json.arrayValue {
            values = array
        } else if let object = json.objectValue {
            values = object.values.flatMap { $0.arrayValue ?? [$0] }
        } else {
            values = []
        }

        return values.enumerated().compactMap { index, value in
            guard let object = value.objectValue else { return nil }
            let id = object["id"]?.stringValue ?? object["groupId"]?.stringValue ?? "group-\(index)"
            let original = object["original"]?.stringValue
                ?? object["before"]?.stringValue
                ?? object["current"]?.stringValue
                ?? "Original resume content"
            let optimized = object["optimized"]?.stringValue
                ?? object["after"]?.stringValue
                ?? object["suggested"]?.stringValue
                ?? "Optimized resume content"
            return ReviewChangeGroup(id: id, original: original, optimized: optimized)
        }
    }
}
