import Foundation
import Observation

@Observable
@MainActor
final class OptimizedResumeViewModel {
    var review: OptimizationReviewResponse?
    var sections: [OptimizedSection] = []
    var atsScore: Int?
    var isLoading = false
    var isApplying = false
    var appliedOptimizationId: String?
    var errorMessage: String?
    var expandedSectionIds: Set<String> = []

    private let apiClient = APIClient()
    private var reviewId: String?

    struct OptimizedSection: Identifiable {
        let id: String
        let title: String
        let badge: ImprovementBadge
        let lines: [BulletLine]
    }

    struct BulletLine: Identifiable {
        let id: String
        let text: String
        let isImproved: Bool
    }

    enum ImprovementBadge: String {
        case improved = "Improved"
        case ats = "ATS"
        case optimized = "Optimized"

        var systemImage: String {
            switch self {
            case .improved: return "sparkles"
            case .ats:      return "checkmark.shield.fill"
            case .optimized: return "bolt.fill"
            }
        }
    }

    var changeGroups: [ReviewChangeGroup] {
        guard let json = review?.review.groupedChangesJSON else { return [] }
        return Self.extractChangeGroups(from: json)
    }

    var acceptedGroupIds: Set<String>

    init() {
        acceptedGroupIds = []
    }

    func load(reviewId: String, token: String?) async {
        guard let token else { errorMessage = "Please sign in first."; return }
        self.reviewId = reviewId
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response: OptimizationReviewResponse = try await apiClient.get(
                endpoint: .optimizationReview(reviewId),
                token: token
            )
            review = response
            let groups = Self.extractChangeGroups(from: response.review.groupedChangesJSON)
            acceptedGroupIds = Set(groups.map(\.id))
            sections = buildSections(from: response)
            atsScore = extractAtsScore(from: response.review.atsPreviewJSON)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyAll(token: String?) async {
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

    func toggleExpanded(_ sectionId: String) {
        if expandedSectionIds.contains(sectionId) {
            expandedSectionIds.remove(sectionId)
        } else {
            expandedSectionIds.insert(sectionId)
        }
    }

    var resumeSnapshot: ResumeSnapshot {
        ResumeSnapshot(
            id: appliedOptimizationId ?? reviewId ?? UUID().uuidString,
            title: review?.jobDescription?.title ?? "Optimized Resume",
            subtitle: review?.jobDescription?.company ?? "Resume preview",
            matchScore: atsScore,
            json: review?.review.optimizedResumeJSON
        )
    }

    // MARK: - Helpers

    private func buildSections(from response: OptimizationReviewResponse) -> [OptimizedSection] {
        guard let json = response.review.optimizedResumeJSON?.objectValue else { return [] }

        let orderedKeys = ["summary", "experience", "skills", "education", "projects", "certifications"]
        let badges: [String: ImprovementBadge] = [
            "summary": .ats,
            "experience": .improved,
            "skills": .optimized,
            "education": .optimized,
            "projects": .improved,
            "certifications": .ats,
        ]

        return orderedKeys.compactMap { key in
            guard let value = json[key] else { return nil }
            let lines = extractLines(from: value)
            guard !lines.isEmpty else { return nil }
            return OptimizedSection(
                id: key,
                title: key.capitalized,
                badge: badges[key] ?? .improved,
                lines: lines.enumerated().map { idx, text in
                    BulletLine(id: "\(key)-\(idx)", text: text, isImproved: idx == 0)
                }
            )
        }
    }

    private func extractLines(from value: JSONValue) -> [String] {
        switch value {
        case .string(let text):  return [text]
        case .array(let arr):    return arr.flatMap { extractLines(from: $0) }
        case .object(let obj):
            if let bullets = obj["bullets"]?.arrayValue {
                return bullets.flatMap { extractLines(from: $0) }
            }
            return obj.values.flatMap { extractLines(from: $0) }
        default: return []
        }
    }

    private func extractAtsScore(from json: JSONValue?) -> Int? {
        guard let obj = json?.objectValue else { return nil }
        return obj["after"]?.intValue ?? obj["optimized"]?.intValue ?? obj["score"]?.intValue
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
            let original = object["original"]?.stringValue ?? object["before"]?.stringValue ?? ""
            let optimized = object["optimized"]?.stringValue ?? object["after"]?.stringValue ?? ""
            return ReviewChangeGroup(id: id, original: original, optimized: optimized)
        }
    }
}
