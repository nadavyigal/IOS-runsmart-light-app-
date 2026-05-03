import Foundation

struct ATSScoreResult: Codable, Sendable {
    let success: Bool?
    let score: ScorePayload?
    let error: String?

    struct ScorePayload: Codable, Sendable {
        let overall: Int?
    }
}

struct ApplicationItem: Codable, Identifiable, Sendable {
    let id: String
    let jobTitle: String?
    let companyName: String?
    let appliedDate: String?
    let status: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case jobTitle = "job_title"
        case companyName = "company_name"
        case appliedDate = "applied_date"
        case status
    }
}

struct CreditTransaction: Codable, Identifiable, Sendable {
    let id: String
    let delta: Int
    let reason: String
    let source: String
    let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case delta
        case reason
        case source
        case createdAt = "created_at"
    }
}

struct CreditsResponse: Codable, Sendable {
    let balance: Int
    let transactions: [CreditTransaction]
}

struct ResumeUploadResponse: Codable, Sendable {
    let success: Bool?
    let resumeId: String?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case resumeId = "resume_id"
        case error
    }
}

struct TailorRequest: Codable, Sendable {
    let resumeId: String
    let jobDescriptionId: String
}

struct TailorResponse: Codable, Sendable {
    let reviewId: String?
    let nextStep: String?
    let error: String?
}

struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let userId: String
    let email: String?
}
