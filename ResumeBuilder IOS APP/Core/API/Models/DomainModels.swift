import Foundation

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// Member access when `JSONValue` is an object (`nil` otherwise).
    subscript(key: String) -> JSONValue? {
        guard case .object(let dict) = self else { return nil }
        return dict[key]
    }
}

struct APIStatusResponse: Codable, Sendable {
    let success: Bool?
    let error: String?
}

/// Response shape returned by POST /api/ats/score (authenticated endpoint).
/// Distinct from ATSScoreResult which is used by /api/public/ats-check.
struct ATSAuthScoreResult: Codable, Sendable {
    let atsScoreOriginal: Int
    let atsScoreOptimized: Int
    let confidence: Double?
    let subscores: ATSSubScores?
    let subscoresOriginal: ATSSubScores?
    let suggestions: [ATSAuthSuggestion]?
    let authQuickWins: [ATSAuthQuickWinSuggestion]?

    init(
        atsScoreOriginal: Int,
        atsScoreOptimized: Int,
        confidence: Double? = nil,
        subscores: ATSSubScores? = nil,
        subscoresOriginal: ATSSubScores? = nil,
        suggestions: [ATSAuthSuggestion]? = nil,
        authQuickWins: [ATSAuthQuickWinSuggestion]? = nil
    ) {
        self.atsScoreOriginal = atsScoreOriginal
        self.atsScoreOptimized = atsScoreOptimized
        self.confidence = confidence
        self.subscores = subscores
        self.subscoresOriginal = subscoresOriginal
        self.suggestions = suggestions
        self.authQuickWins = authQuickWins
    }

    private enum CodingKeys: String, CodingKey {
        case atsScoreOriginal  = "ats_score_original"
        case atsScoreOptimized = "ats_score_optimized"
        case confidence
        case subscores
        case subscoresOriginal = "subscores_original"
        case suggestions
        case authQuickWins = "quick_wins"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func decodeFlexibleInt(for key: CodingKeys) -> Int? {
            if let value = try? c.decode(Int.self, forKey: key) {
                return value
            }
            if let value = try? c.decode(Double.self, forKey: key) {
                let scaled = value <= 1 ? value * 100 : value
                return Int(scaled.rounded())
            }
            return nil
        }
        guard
            let orig = decodeFlexibleInt(for: .atsScoreOriginal),
            let opt = decodeFlexibleInt(for: .atsScoreOptimized)
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing ATS score fields"))
        }
        self.atsScoreOriginal = orig
        self.atsScoreOptimized = opt
        self.confidence = try? c.decode(Double.self, forKey: .confidence)
        self.subscores = try c.decodeIfPresent(ATSSubScores.self, forKey: .subscores)
        self.subscoresOriginal = try c.decodeIfPresent(ATSSubScores.self, forKey: .subscoresOriginal)
        self.suggestions = try c.decodeIfPresent([ATSAuthSuggestion].self, forKey: .suggestions)
        self.authQuickWins = try c.decodeIfPresent([ATSAuthQuickWinSuggestion].self, forKey: .authQuickWins)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(atsScoreOriginal, forKey: .atsScoreOriginal)
        try c.encode(atsScoreOptimized, forKey: .atsScoreOptimized)
        try c.encodeIfPresent(confidence, forKey: .confidence)
        try c.encodeIfPresent(subscores, forKey: .subscores)
        try c.encodeIfPresent(subscoresOriginal, forKey: .subscoresOriginal)
        try c.encodeIfPresent(suggestions, forKey: .suggestions)
        try c.encodeIfPresent(authQuickWins, forKey: .authQuickWins)
    }
}

/// ATS v2 engine subscores (see `src/lib/ats/types.ts` — SubScores).
struct ATSSubScores: Codable, Sendable, Equatable {
    let keyword_exact: Int?
    let keyword_phrase: Int?
    let semantic_relevance: Int?
    let title_alignment: Int?
    let metrics_presence: Int?
    let section_completeness: Int?
    let format_parseability: Int?
    let recency_fit: Int?

    enum CodingKeys: String, CodingKey {
        case keyword_exact
        case keyword_phrase
        case semantic_relevance
        case title_alignment
        case metrics_presence
        case section_completeness
        case format_parseability
        case recency_fit
    }

    init(
        keyword_exact: Int? = nil,
        keyword_phrase: Int? = nil,
        semantic_relevance: Int? = nil,
        title_alignment: Int? = nil,
        metrics_presence: Int? = nil,
        section_completeness: Int? = nil,
        format_parseability: Int? = nil,
        recency_fit: Int? = nil
    ) {
        self.keyword_exact = keyword_exact
        self.keyword_phrase = keyword_phrase
        self.semantic_relevance = semantic_relevance
        self.title_alignment = title_alignment
        self.metrics_presence = metrics_presence
        self.section_completeness = section_completeness
        self.format_parseability = format_parseability
        self.recency_fit = recency_fit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyword_exact = Self.decodeFlexibleInt(container: c, key: .keyword_exact)
        keyword_phrase = Self.decodeFlexibleInt(container: c, key: .keyword_phrase)
        semantic_relevance = Self.decodeFlexibleInt(container: c, key: .semantic_relevance)
        title_alignment = Self.decodeFlexibleInt(container: c, key: .title_alignment)
        metrics_presence = Self.decodeFlexibleInt(container: c, key: .metrics_presence)
        section_completeness = Self.decodeFlexibleInt(container: c, key: .section_completeness)
        format_parseability = Self.decodeFlexibleInt(container: c, key: .format_parseability)
        recency_fit = Self.decodeFlexibleInt(container: c, key: .recency_fit)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(keyword_exact, forKey: .keyword_exact)
        try c.encodeIfPresent(keyword_phrase, forKey: .keyword_phrase)
        try c.encodeIfPresent(semantic_relevance, forKey: .semantic_relevance)
        try c.encodeIfPresent(title_alignment, forKey: .title_alignment)
        try c.encodeIfPresent(metrics_presence, forKey: .metrics_presence)
        try c.encodeIfPresent(section_completeness, forKey: .section_completeness)
        try c.encodeIfPresent(format_parseability, forKey: .format_parseability)
        try c.encodeIfPresent(recency_fit, forKey: .recency_fit)
    }

    private static func decodeFlexibleInt(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return Int(value.rounded())
        }
        return nil
    }
}

struct ATSAuthSuggestion: Codable, Identifiable, Sendable {
    let id: String
    let text: String?
    let category: String?
    let quickWin: Bool?
    let estimatedGain: Int?

    init(id: String, text: String?, category: String?, quickWin: Bool?, estimatedGain: Int?) {
        self.id = id
        self.text = text
        self.category = category
        self.quickWin = quickWin
        self.estimatedGain = estimatedGain
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case category
        case quickWin = "quick_win"
        case estimatedGain = "estimated_gain"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try c.decodeIfPresent(String.self, forKey: .text)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        quickWin = try c.decodeIfPresent(Bool.self, forKey: .quickWin)
        if let ig = try? c.decode(Int.self, forKey: .estimatedGain) {
            estimatedGain = ig
        } else if let d = try? c.decode(Double.self, forKey: .estimatedGain) {
            estimatedGain = Int(d.rounded())
        } else {
            estimatedGain = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(quickWin, forKey: .quickWin)
        try c.encodeIfPresent(estimatedGain, forKey: .estimatedGain)
    }
}

struct ATSAuthQuickWinSuggestion: Codable, Identifiable, Sendable {
    let id: String
    let originalText: String?
    let optimizedText: String?
    let estimatedImpact: Int?
    let rationale: String?
    let improvementType: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case originalText = "original_text"
        case optimizedText = "optimized_text"
        case estimatedImpact = "estimated_impact"
        case rationale
        case improvementType = "improvement_type"
    }
}

/// POST /api/ats/rescan — client uses nested `scores` for headline ATS refresh.
struct ATSRescanResponse: Decodable, Sendable {
    let success: Bool?
    let optimizedScore: Int?
    let originalScore: Int?

    private enum CodingKeys: String, CodingKey {
        case success
        case scores
    }

    private struct FlexibleScores: Decodable, Sendable {
        let original: LossyCodingInt?
        let optimized: LossyCodingInt?
    }

    /// Decodes ints or fractional numbers (`0.82` scaled by API variants).
    private struct LossyCodingInt: Decodable, Sendable {
        let value: Int

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) {
                value = i
            } else if let d = try? c.decode(Double.self) {
                let scaled = d <= 1 ? d * 100 : d
                value = Int(scaled.rounded())
            } else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Cannot decode ATS score fraction")
            }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success)
        if let nested = try c.decodeIfPresent(FlexibleScores.self, forKey: .scores) {
            originalScore = nested.original?.value
            optimizedScore = nested.optimized?.value
        } else {
            originalScore = nil
            optimizedScore = nil
        }
    }

    init(success: Bool?, optimizedScore: Int?, originalScore: Int?) {
        self.success = success
        self.optimizedScore = optimizedScore
        self.originalScore = originalScore
    }
}

/// Response shape returned by GET /api/resumes/{id}.
struct ResumeTextResponse: Codable, Sendable {
    let rawText: String

    private enum CodingKeys: String, CodingKey {
        case rawText = "raw_text"
    }
}

struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

struct OptimizationSummary: Codable, Sendable {
    let atsScore: Int
    let contentScore: Int?
    let designScore: Int?
    let keywordScore: Int?

    init(item: OptimizationHistoryItem) {
        atsScore = item.matchScorePercent
        contentScore = item.contentScorePercent
        designScore = item.designScorePercent
        keywordScore = item.keywordScorePercent
    }
}

struct OptimizationHistoryResponse: Codable, Sendable {
    let success: Bool?
    let optimizations: [OptimizationHistoryItem]?
    let data: [OptimizationHistoryItem]?
    let items: [OptimizationHistoryItem]?
    let pagination: PaginationMeta?

    var allItems: [OptimizationHistoryItem] {
        optimizations ?? data ?? items ?? []
    }
}

struct PaginationMeta: Codable, Sendable {
    let page: Int?
    let limit: Int?
    let total: Int?
    let hasMore: Bool?
    let totalPages: Int?
}

struct BulkDeleteResponse: Codable, Sendable {
    let success: Bool
    let deleted: Int?
    let errors: [BulkDeleteError]?

    struct BulkDeleteError: Codable, Sendable {
        let id: String
        let error: String
    }
}

struct OptimizationHistoryItem: Codable, Identifiable, Sendable {
    let id: String
    let createdAt: String
    let jobTitle: String?
    let company: String?
    let matchScorePercent: Int
    let contentScorePercent: Int?
    let designScorePercent: Int?
    let keywordScorePercent: Int?
    let status: String?
    let jobUrl: String?
    let templateKey: String?
    let resumeId: String?
    /// Grouped optimization review (`/api/v1/optimization-reviews/:id`), when the backend can match a review run.
    let reviewId: String?

    init(
        id: String,
        createdAt: String,
        jobTitle: String?,
        company: String?,
        matchScorePercent: Int,
        contentScorePercent: Int? = nil,
        designScorePercent: Int? = nil,
        keywordScorePercent: Int? = nil,
        status: String? = nil,
        jobUrl: String? = nil,
        templateKey: String? = nil,
        resumeId: String? = nil,
        reviewId: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.jobTitle = jobTitle
        self.company = company
        self.matchScorePercent = matchScorePercent
        self.contentScorePercent = contentScorePercent
        self.designScorePercent = designScorePercent
        self.keywordScorePercent = keywordScorePercent
        self.status = status
        self.jobUrl = jobUrl
        self.templateKey = templateKey
        self.resumeId = resumeId
        self.reviewId = reviewId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        id = try container.decodeString(for: ["id", "optimizationId", "optimization_id"]) ?? UUID().uuidString
        createdAt = try container.decodeString(for: ["createdAt", "created_at"]) ?? ""
        jobTitle = try container.decodeString(for: ["jobTitle", "job_title", "title"])
        company = try container.decodeString(for: ["company", "companyName", "company_name"])
        matchScorePercent = try container.decodePercent(for: ["matchScore", "match_score", "atsScore", "ats_score"]) ?? 0
        contentScorePercent = try container.decodePercent(for: ["contentScore", "content_score"])
        designScorePercent = try container.decodePercent(for: ["designScore", "design_score"])
        keywordScorePercent = try container.decodePercent(for: ["keywordScore", "keyword_score", "keywordsScore", "keywords_score"])
        status = try container.decodeString(for: ["status"])
        jobUrl = try container.decodeString(for: ["jobUrl", "job_url"])
        templateKey = try container.decodeString(for: ["templateKey", "template_key"])
        resumeId = try container.decodeString(for: ["resumeId", "resume_id"])
        reviewId = try container.decodeString(for: ["reviewId", "review_id"])
    }

    var filename: String {
        let title = [jobTitle, company]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return title.isEmpty ? "Optimized Resume" : title
    }

    var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: createdAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .none
            return display.string(from: date)
        }
        return createdAt
    }
}

private extension KeyedDecodingContainer where K == DynamicCodingKey {
    func decodeString(for keys: [String]) throws -> String? {
        for key in keys {
            let codingKey = DynamicCodingKey(key)
            if let value = try decodeIfPresent(String.self, forKey: codingKey) {
                return value
            }
            if let value = try decodeIfPresent(Int.self, forKey: codingKey) {
                return String(value)
            }
        }
        return nil
    }

    func decodePercent(for keys: [String]) throws -> Int? {
        for key in keys {
            let codingKey = DynamicCodingKey(key)
            if let value = try decodeIfPresent(Int.self, forKey: codingKey) {
                return normalizePercent(Double(value))
            }
            if let value = try decodeIfPresent(Double.self, forKey: codingKey) {
                return normalizePercent(value)
            }
            if let value = try decodeIfPresent(String.self, forKey: codingKey),
               let number = Double(value) {
                return normalizePercent(number)
            }
        }
        return nil
    }

    private func normalizePercent(_ value: Double) -> Int {
        let percent = value <= 1 ? value * 100 : value
        return min(100, max(0, Int(percent.rounded())))
    }

    func decodeInt(for keys: [String]) throws -> Int? {
        for key in keys {
            let codingKey = DynamicCodingKey(key)
            if let value = try decodeIfPresent(Int.self, forKey: codingKey) {
                return value
            }
            if let value = try decodeIfPresent(Double.self, forKey: codingKey) {
                return Int(value.rounded())
            }
        }
        return nil
    }
}

struct ATSScoreResult: Codable, Sendable {
    let success: Bool?
    let score: ScorePayload?
    let preview: PreviewPayload?
    let quickWins: [QuickWin]?
    let checksRemaining: Int?
    let sessionId: String?
    let error: String?

    struct ScorePayload: Codable, Sendable {
        let overall: Int?
        let timestamp: String?
    }

    struct PreviewPayload: Codable, Sendable {
        let topIssues: [ATSIssue]
        let totalIssues: Int?
        let lockedCount: Int?
    }
}

struct ATSIssue: Codable, Identifiable, Sendable {
    var id: String { "\(category ?? severity ?? "issue")-\(message ?? text ?? suggestion ?? "ats")" }
    let category: String?
    let severity: String?
    let message: String?
    let text: String?
    let suggestion: String?
}

struct QuickWin: Codable, Identifiable, Sendable {
    var id: String { "\(keyword ?? title ?? action ?? reason ?? "quick-win")" }
    let title: String?
    let action: String?
    let keyword: String?
    let impact: String?
    let reason: String?
}

/// Application row from `GET /api/v1/applications` or embedded `application` on detail.
struct ApplicationItem: Codable, Identifiable, Sendable {
    let id: String
    let jobTitle: String?
    let companyName: String?
    let appliedDate: String?
    let status: String?
    let applyClickedAt: String?
    let atsScore: Int?
    let optimizationId: String?
    let optimizedResumeURL: String?
    let optimizedResumeId: String?
    let jobExtraction: JSONValue?
    let contact: JSONValue?

    init(
        id: String,
        jobTitle: String? = nil,
        companyName: String? = nil,
        appliedDate: String? = nil,
        status: String? = nil,
        applyClickedAt: String? = nil,
        atsScore: Int? = nil,
        optimizationId: String? = nil,
        optimizedResumeURL: String? = nil,
        optimizedResumeId: String? = nil,
        jobExtraction: JSONValue? = nil,
        contact: JSONValue? = nil
    ) {
        self.id = id
        self.jobTitle = jobTitle
        self.companyName = companyName
        self.appliedDate = appliedDate
        self.status = status
        self.applyClickedAt = applyClickedAt
        self.atsScore = atsScore
        self.optimizationId = optimizationId
        self.optimizedResumeURL = optimizedResumeURL
        self.optimizedResumeId = optimizedResumeId
        self.jobExtraction = jobExtraction
        self.contact = contact
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case jobTitle = "job_title"
        case companyName = "company_name"
        case appliedDate = "applied_date"
        case status
        case applyClickedAt = "apply_clicked_at"
        case atsScore = "ats_score"
        case optimizationId = "optimization_id"
        case optimizedResumeURL = "optimized_resume_url"
        case optimizedResumeId = "optimized_resume_id"
        case jobExtraction = "job_extraction"
        case contact
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        jobTitle = try c.decodeIfPresent(String.self, forKey: .jobTitle)
        companyName = try c.decodeIfPresent(String.self, forKey: .companyName)
        appliedDate = try c.decodeIfPresent(String.self, forKey: .appliedDate)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        applyClickedAt = try c.decodeIfPresent(String.self, forKey: .applyClickedAt)
        optimizationId = try c.decodeIfPresent(String.self, forKey: .optimizationId)
        optimizedResumeURL = try c.decodeIfPresent(String.self, forKey: .optimizedResumeURL)
        optimizedResumeId = try c.decodeIfPresent(String.self, forKey: .optimizedResumeId)
        jobExtraction = try c.decodeIfPresent(JSONValue.self, forKey: .jobExtraction)
        contact = try c.decodeIfPresent(JSONValue.self, forKey: .contact)
        if let intScore = try? c.decode(Int.self, forKey: .atsScore) {
            atsScore = intScore
        } else if let d = try? c.decode(Double.self, forKey: .atsScore) {
            let scaled = d <= 1 ? d * 100 : d
            atsScore = Int(scaled.rounded())
        } else {
            atsScore = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(jobTitle, forKey: .jobTitle)
        try c.encodeIfPresent(companyName, forKey: .companyName)
        try c.encodeIfPresent(appliedDate, forKey: .appliedDate)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(applyClickedAt, forKey: .applyClickedAt)
        try c.encodeIfPresent(atsScore, forKey: .atsScore)
        try c.encodeIfPresent(optimizationId, forKey: .optimizationId)
        try c.encodeIfPresent(optimizedResumeURL, forKey: .optimizedResumeURL)
        try c.encodeIfPresent(optimizedResumeId, forKey: .optimizedResumeId)
        try c.encodeIfPresent(jobExtraction, forKey: .jobExtraction)
        try c.encodeIfPresent(contact, forKey: .contact)
    }
}

struct ApplicationsListEnvelope: Codable, Sendable {
    let success: Bool?
    let applications: [ApplicationItem]
}

struct ApplicationDetailEnvelope: Codable, Sendable {
    let success: Bool?
    let application: ApplicationItem
    let htmlUrl: String?
    let jsonUrl: String?

    enum CodingKeys: String, CodingKey {
        case success
        case application
        case htmlUrl
        case jsonUrl
    }
}

struct ApplicationExpertReportsEnvelope: Codable, Sendable {
    let success: Bool?
    let reports: [ApplicationExpertReportItem]

    enum CodingKeys: String, CodingKey {
        case success
        case reports
    }

    init(success: Bool? = nil, reports: [ApplicationExpertReportItem] = []) {
        self.success = success
        self.reports = reports
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success)
        reports = try c.decodeIfPresent([ApplicationExpertReportItem].self, forKey: .reports) ?? []
    }
}

/// Saved expert run metadata linked to an application (from `GET .../expert-reports`).
struct ApplicationExpertReportItem: Codable, Identifiable, Sendable {
    let id: String
    let reportTitle: String?
    let workflowType: String?
    let savedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reportTitle = "report_title"
        case workflowType = "workflow_type"
        case savedAt = "saved_at"
    }
}

enum ApplicationJobExtractionKeywords {
    /// Best-effort: first string snippets from scraped job bullets (parity with web compare heuristics).
    static func topKeywords(from extraction: JSONValue?, maxCount: Int = 3) -> [String] {
        guard let extraction else { return [] }
        let keys = ["requirements", "qualifications", "responsibilities", "nice_to_have"]
        var out: [String] = []
        for key in keys {
            guard out.count < maxCount, let arr = extraction[key], case .array(let items) = arr else { continue }
            for el in items {
                guard out.count < maxCount else { break }
                if case .string(let s) = el, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count > 80 {
                        out.append(String(trimmed.prefix(77)) + "…")
                    } else {
                        out.append(trimmed)
                    }
                }
            }
        }
        return out
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
    let jobDescriptionId: String?
    let reviewId: String?
    let nextStep: String?
    let matchScore: Int?
    let keyImprovements: [String]?
    let missingKeywords: [String]?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case resumeId
        case jobDescriptionId
        case reviewId
        case nextStep
        case matchScore
        case keyImprovements
        case missingKeywords
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

struct IAPVerifyResponse: Codable, Sendable {
    let success: Bool?
    let creditsGranted: Int?
    let balance: Int?
    let error: String?
}

struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let userId: String
    let email: String?
}

// MARK: - Chat (GET / POST /api/v1/chat…)

enum ChatParticipant: String, Codable, Sendable {
    case user
    case ai
}

/// Row from `chat_sessions`.
struct ChatSessionRecord: Codable, Identifiable, Sendable {
    let id: String
    let optimizationId: String?
    let status: String?
    let createdAt: String?
    let lastActivityAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case optimizationId = "optimization_id"
        case status
        case createdAt = "created_at"
        case lastActivityAt = "last_activity_at"
    }
}

/// Row from `chat_messages`; `sender` is `user` or `ai` from API.
struct ChatMessageRecord: Codable, Identifiable, Sendable {
    let id: String
    let sessionId: String?
    let sender: ChatParticipant?
    /// API field name `sender`; some proxies may expose `role`
    let content: String
    let createdAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case sender
        case role
        case content
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        if let sender = try c.decodeIfPresent(ChatParticipant.self, forKey: .sender) {
            self.sender = sender
        } else if let roleRaw = try c.decodeIfPresent(String.self, forKey: .role) {
            self.sender = ChatParticipant(rawValue: roleRaw) ?? ChatParticipant.ai
        } else {
            sender = nil
        }
        content = try c.decode(String.self, forKey: .content)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(sessionId, forKey: .sessionId)
        try c.encodeIfPresent(sender, forKey: .sender)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }

    /// UI role (defaults assistant for unknown senders except user).
    var uiRole: ChatParticipant {
        sender ?? .ai
    }
}

/// Affected field from ATS pending-change payloads (`originalValue` / `newValue` may be heterogeneous JSON).
struct ChatAffectedField: Codable, Sendable {
    let sectionId: String
    let field: String?
    let originalValue: JSONValue?
    let newValue: JSONValue?
    let changeType: String?

    private enum CodingKeys: String, CodingKey {
        case sectionId
        case section_id
        case field
        case fieldPath = "fieldPath"
        case field_path = "field_path"
        case originalValue
        case original_value = "original_value"
        case after
        case newValue
        case new_value = "new_value"
        case changeType
        case change_type = "change_type"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sectionId =
            try c.decodeIfPresent(String.self, forKey: .sectionId)
            ?? c.decodeIfPresent(String.self, forKey: .section_id) ?? ""

        field =
            try c.decodeIfPresent(String.self, forKey: .field)
                ?? c.decodeIfPresent(String.self, forKey: .fieldPath)
                ?? c.decodeIfPresent(String.self, forKey: .field_path)

        originalValue =
            try c.decodeIfPresent(JSONValue.self, forKey: .originalValue)
                ?? c.decodeIfPresent(JSONValue.self, forKey: .original_value)

        if let nv = try c.decodeIfPresent(JSONValue.self, forKey: .newValue) {
            newValue = nv
        } else if let nv = try c.decodeIfPresent(JSONValue.self, forKey: .new_value) {
            newValue = nv
        } else if let nv = try c.decodeIfPresent(JSONValue.self, forKey: .after) {
            newValue = nv
        } else {
            newValue = nil
        }

        changeType =
            try c.decodeIfPresent(String.self, forKey: .changeType)
                ?? c.decodeIfPresent(String.self, forKey: .change_type)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sectionId, forKey: .sectionId)
        try c.encodeIfPresent(field, forKey: .field)
        try c.encodeIfPresent(originalValue, forKey: .originalValue)
        if let newValue {
            try c.encode(newValue, forKey: .newValue)
        }
        try c.encodeIfPresent(changeType, forKey: .changeType)
    }
}

struct ChatAmendmentRecord: Codable, Identifiable, Sendable {
    let id: String
    let status: String?
}

/// Mirrors web `PendingChange` (camelCase or snake_case JSON).
struct ChatPendingChange: Decodable, Identifiable, Sendable {
    let suggestionId: String
    let suggestionNumber: Int
    let suggestionText: String
    let description: String
    let affectedFields: [ChatAffectedField]?
    let amendments: [ChatAmendmentRecord]?
    var status: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicCodingKey.self)
        suggestionId =
            try c.decodeString(for: ["suggestionId", "suggestion_id"]) ?? UUID().uuidString
        suggestionNumber =
            try c.decodeInt(for: ["suggestionNumber", "suggestion_number"]) ?? 0
        suggestionText =
            try c.decodeString(for: ["suggestionText", "suggestion_text"]) ?? ""
        description =
            try c.decodeString(for: ["description"]) ?? suggestionText
        affectedFields =
            try c.decodeIfPresent([ChatAffectedField].self, forKey: DynamicCodingKey("affectedFields"))
                ?? c.decodeIfPresent([ChatAffectedField].self, forKey: DynamicCodingKey("affected_fields"))
        amendments =
            try c.decodeIfPresent([ChatAmendmentRecord].self, forKey: DynamicCodingKey("amendments"))
        status = try c.decodeString(for: ["status"])
    }

    var id: String { suggestionId }
}

/// POST `/api/v1/chat` decode (subset used by native client).
struct ChatSendMessageResponseDTO: Decodable, Sendable {
    let sessionId: String?
    let messageId: String?
    let aiResponse: String?
    let pendingChanges: [ChatPendingChange]?

    private enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case messageId = "message_id"
        case aiResponse = "ai_response"
        case pendingChanges = "pending_changes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        messageId = try c.decodeIfPresent(String.self, forKey: .messageId)
        aiResponse = try c.decodeIfPresent(String.self, forKey: .aiResponse)
        pendingChanges =
            try c.decodeIfPresent([ChatPendingChange].self, forKey: .pendingChanges)
    }
}

/// GET `/api/v1/chat/sessions` list wrapper.
struct ChatSessionListEnvelope: Decodable, Sendable {
    let sessions: [ChatSessionRecord]?
    let total: Int?
}

/// GET `/api/v1/chat/sessions/{id}` detail.
struct ChatSessionDetailEnvelope: Decodable, Sendable {
    let session: ChatSessionRecord?
    let messages: [ChatMessageRecord]?
    let totalMessages: Int?

    private enum CodingKeys: String, CodingKey {
        case session
        case messages
        case totalMessages = "total_messages"
    }
}

/// GET `/api/v1/chat/sessions/{id}/messages` pagination.
struct ChatMessagesPageEnvelope: Decodable, Sendable {
    let messages: [ChatMessageRecord]?
    let total: Int?
    let page: Int?
    let pageSize: Int?
    let hasMore: Bool?

    private enum CodingKeys: String, CodingKey {
        case messages, total, page
        case pageSize = "page_size"
        case hasMore = "has_more"
    }
}

/// POST `/api/v1/chat/approve-change`
struct ChatApproveChangeResponseDTO: Decodable, Sendable {
    let success: Bool?
    let updatedResume: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case success
        case updatedResume = "updated_resume"
    }
}

/// POST `/api/v1/chat/sessions/{id}/apply`
struct ChatApplyAmendmentResponseDTO: Decodable, Sendable {
    let updatedContent: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case updatedContent = "updated_content"
    }
}

// MARK: - Expert workflows (`/api/v1/expert-workflows`)

enum ExpertWorkflowType: String, Codable, Sendable, CaseIterable {
    case fullResumeRewrite = "full_resume_rewrite"
    case achievementQuantifier = "achievement_quantifier"
    case atsOptimizationReport = "ats_optimization_report"
    case professionalSummaryLab = "professional_summary_lab"
    case coverLetterArchitect = "cover_letter_architect"
    case screeningAnswerStudio = "screening_answer_studio"
}

extension ExpertWorkflowType: Identifiable {
    var id: String { rawValue }
}

struct ExpertAtsImpactEstimate: Codable, Sendable, Equatable {
    let before: Double?
    let after: Double?
    let delta: Double?
    let confidenceNote: String?

    init(before: Double?, after: Double?, delta: Double?, confidenceNote: String?) {
        self.before = before
        self.after = after
        self.delta = delta
        self.confidenceNote = confidenceNote
    }

    private enum CodingKeys: String, CodingKey {
        case before, after, delta
        case confidenceNote = "confidence_note"
    }
}

/// Structured report surfaced in model output (`output.report`).
struct ExpertWorkflowReportEnvelope: Codable, Sendable, Equatable {
    let headline: String?
    let executiveSummary: String?
    let priorityActions: [String]?
    let evidenceGaps: [String]?
    let atsImpactEstimate: ExpertAtsImpactEstimate?

    private enum CodingKeys: String, CodingKey {
        case headline
        case executiveSummary = "executive_summary"
        case priorityActions = "priority_actions"
        case evidenceGaps = "evidence_gaps"
        case atsImpactEstimate = "ats_impact_estimate"
    }
}

/// Convenience UI bundle parsed from arbitrary JSON (`output`).
struct ExpertReportDisplayModel: Sendable, Equatable {
    let headline: String
    let executiveSummary: String
    let priorityActions: [String]
    let evidenceGaps: [String]
    let atsImpact: ExpertAtsImpactEstimate?

    init(
        headline: String,
        executiveSummary: String,
        priorityActions: [String],
        evidenceGaps: [String],
        atsImpact: ExpertAtsImpactEstimate?
    ) {
        self.headline = headline
        self.executiveSummary = executiveSummary
        self.priorityActions = priorityActions
        self.evidenceGaps = evidenceGaps
        self.atsImpact = atsImpact
    }
}

struct ExpertAtsImpactResult: Codable, Sendable, Equatable {
    let before: Double?
    let after: Double?
    let delta: Double?
}

/// POST `/api/v1/expert-workflows/run` JSON body succeeds (200).
struct ExpertWorkflowRunCreateResponseDTO: Decodable, Sendable {
    let workflowType: String?
    let runId: String
    let status: String
    /// Parsed expert model JSON (rewrite payload, variants, bullets, …).
    let output: JSONValue
    let needsUserInput: Bool?
    let missingEvidence: [String]?

    private enum CodingKeys: String, CodingKey {
        case workflowType = "workflow_type"
        case runId = "run_id"
        case status
        case output
        case needsUserInput = "needs_user_input"
        case missingEvidence = "missing_evidence"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workflowType = try c.decodeIfPresent(String.self, forKey: .workflowType)
        runId = try c.decodeIfPresent(String.self, forKey: .runId) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "completed"
        output = try c.decodeIfPresent(JSONValue.self, forKey: .output) ?? .object([:])
        needsUserInput = try c.decodeIfPresent(Bool.self, forKey: .needsUserInput)
        missingEvidence =
            try c.decodeIfPresent([String].self, forKey: .missingEvidence) ?? []
    }
}

/// GET `/api/v1/expert-workflows/runs/:id`.
struct ExpertWorkflowRunDetailEnvelope: Decodable, Sendable {
    let run: ExpertWorkflowRunRow?

    enum CodingKeys: String, CodingKey {
        case run
    }
}

struct ExpertWorkflowRunRow: Decodable, Sendable {
    let id: String
    let status: String?
    let workflowType: String?
    let outputJson: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case id, status
        case workflowType = "workflow_type"
        case outputJson = "output_json"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status)
        workflowType = try c.decodeIfPresent(String.self, forKey: .workflowType)
        outputJson = try c.decodeIfPresent(JSONValue.self, forKey: .outputJson)
    }
}

/// POST `/api/v1/expert-workflows/runs/:id/apply`.
struct ExpertWorkflowApplyResponseDTO: Decodable, Sendable {
    let success: Bool?
    let error: String?
    let workflowType: String?
    let updatedFields: [String]
    let atsImpact: ExpertAtsImpactResult?
    let applyMode: String?
    let selectionIndex: Int?
    let appliedAssets: [String]?
    let newAtsScore: Double?

    private enum CodingKeys: String, CodingKey {
        case success, error
        case workflowType = "workflow_type"
        case updatedFields = "updated_fields"
        case atsImpact = "ats_impact"
        case applyMode = "apply_mode"
        case selectionIndex = "selection_index"
        case appliedAssets = "applied_assets"
        case newAtsScore = "new_ats_score"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decodeIfPresent(Bool.self, forKey: .success)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        workflowType = try c.decodeIfPresent(String.self, forKey: .workflowType)
        updatedFields = try c.decodeIfPresent([String].self, forKey: .updatedFields) ?? []
        atsImpact = try c.decodeIfPresent(ExpertAtsImpactResult.self, forKey: .atsImpact)
        applyMode = try c.decodeIfPresent(String.self, forKey: .applyMode)
        if let sid = try c.decodeIfPresent(Int.self, forKey: .selectionIndex) {
            selectionIndex = sid
        } else if let dn = try c.decodeIfPresent(Double.self, forKey: .selectionIndex) {
            selectionIndex = Int(dn.rounded())
        } else {
            selectionIndex = nil
        }
        appliedAssets =
            try c.decodeIfPresent([String].self, forKey: .appliedAssets)
        if let d = try c.decodeIfPresent(Double.self, forKey: .newAtsScore) {
            newAtsScore = d
        } else if let i = try c.decodeIfPresent(Int.self, forKey: .newAtsScore) {
            newAtsScore = Double(i)
        } else {
            newAtsScore = nil
        }
    }
}

// MARK: - Phase 6 — Optimization review

struct OptimizationReviewEnvelope: Decodable, Sendable {
    let review: OptimizationReviewRunDTO
    let resume: OptimizationReviewResumeDTO?
    let jobDescription: OptimizationReviewJobDescriptionDTO?

    private enum CodingKeys: String, CodingKey {
        case review
        case resume
        case jobDescription = "jobDescription"
    }
}

struct OptimizationReviewResumeDTO: Decodable, Sendable {
    let filename: String?
    let rawText: String?

    private enum CodingKeys: String, CodingKey {
        case filename
        case rawText = "raw_text"
    }
}

struct OptimizationReviewJobDescriptionDTO: Decodable, Sendable {
    let title: String?
    let company: String?
}

struct OptimizationReviewRunDTO: Decodable, Sendable {
    let id: String
    let groupedChanges: [ReviewChangeGroupDTO]
    let atsPreview: ReviewATSPreviewDTO?
    let appliedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case groupedChanges = "grouped_changes_json"
        case atsPreview = "ats_preview_json"
        case appliedAt = "applied_at"
    }
}

struct ReviewATSPreviewDTO: Decodable, Sendable {
    let before: Double?
    let after: Double?
    let delta: Double?
}

struct ReviewChangeGroupDTO: Decodable, Identifiable, Sendable {
    let id: String
    let section: String
    let title: String
    let summary: String
    let beforeExcerpt: String
    let afterExcerpt: String

    private enum CodingKeys: String, CodingKey {
        case id, section, title, summary
        case beforeExcerpt = "before_excerpt"
        case afterExcerpt = "after_excerpt"
    }
}

struct OptimizationReviewApplyResponseDTO: Decodable, Sendable {
    let optimizationId: String?
    let approvedCount: Int?
    let rejectedCount: Int?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case optimizationId
        case optimization_id
        case approvedCount
        case rejectedCount
        case error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        optimizationId =
            try c.decodeIfPresent(String.self, forKey: .optimizationId)
            ?? c.decodeIfPresent(String.self, forKey: .optimization_id)
        approvedCount = try c.decodeIfPresent(Int.self, forKey: .approvedCount)
        rejectedCount = try c.decodeIfPresent(Int.self, forKey: .rejectedCount)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
}

// MARK: - Optimization detail (Phase 3 section fetch)

struct OptimizationDetailDTO: Decodable, Sendable {
    let sections: [OptimizedResumeSection]
    let jobTitle: String?
    let company: String?
    let atsScoreBefore: Int?
    let atsScoreAfter: Int?
}

// MARK: - Phase 6 — Modification history

struct ModificationHistoryEnvelope: Decodable, Sendable {
    let modifications: [ContentModificationDTO]
    let total: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modifications = try c.decodeIfPresent([ContentModificationDTO].self, forKey: .modifications) ?? []
        total = try c.decodeIfPresent(Int.self, forKey: .total)
    }

    private enum CodingKeys: String, CodingKey {
        case modifications
        case total
    }
}

struct ContentModificationDTO: Decodable, Identifiable, Sendable {
    let id: String
    let optimizationId: String?
    let createdAt: String?
    let fieldPath: String?
    let operationType: String?
    let oldValue: JSONValue?
    let newValue: JSONValue?
    let atsScoreBefore: Double?
    let atsScoreAfter: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case optimizationId = "optimization_id"
        case createdAt = "created_at"
        case fieldPath = "field_path"
        case operationType = "operation_type"
        case operation
        case oldValue = "old_value"
        case newValue = "new_value"
        case atsScoreBefore = "ats_score_before"
        case atsScoreAfter = "ats_score_after"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        optimizationId = try c.decodeIfPresent(String.self, forKey: .optimizationId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        fieldPath = try c.decodeIfPresent(String.self, forKey: .fieldPath)
        operationType =
            try c.decodeIfPresent(String.self, forKey: .operationType)
            ?? c.decodeIfPresent(String.self, forKey: .operation)
        oldValue = ContentModificationDTO.decodeFlexibleValue(c, key: .oldValue)
        newValue = ContentModificationDTO.decodeFlexibleValue(c, key: .newValue)
        atsScoreBefore = try c.decodeIfPresent(Double.self, forKey: .atsScoreBefore)
        atsScoreAfter = try c.decodeIfPresent(Double.self, forKey: .atsScoreAfter)
    }

    private static func decodeFlexibleValue(
        _ c: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> JSONValue? {
        if let j = try? c.decode(JSONValue.self, forKey: key) { return j }
        if let s = try? c.decode(String.self, forKey: key) {
            if let data = s.data(using: .utf8),
               let obj = try? JSONDecoder().decode(JSONValue.self, from: data) {
                return obj
            }
            return .string(s)
        }
        return nil
    }
}

struct ModificationRevertResponseDTO: Decodable, Sendable {
    let success: Bool?
    let message: String?
    let error: String?
}

// MARK: - Phase 6 — Style history

struct StyleHistoryEnvelope: Decodable, Sendable {
    let history: [StyleHistoryEntryDTO]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        history = try c.decodeIfPresent([StyleHistoryEntryDTO].self, forKey: .history) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case history
    }
}

struct StyleHistoryEntryDTO: Decodable, Identifiable, Sendable {
    let id: String
    let createdAt: String?
    let styleType: String?
    let oldValue: String?
    let newValue: String?
    let customizationId: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case styleType = "style_type"
        case oldValue = "old_value"
        case newValue = "new_value"
        case customizationId = "customization_id"
    }
}

struct StyleRevertResponseDTO: Decodable, Sendable {
    let success: Bool?
    let message: String?
    let error: String?
}

struct DesignUndoResponseDTO: Decodable, Sendable {
    let message: String?
    let error: String?
}
// MARK: - Resume Preview Models

struct ResumeSection: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let lines: [String]
}

struct ResumeSnapshot: Sendable {
    let id: String
    let title: String
    let subtitle: String
    let matchScore: Int
    let json: JSONValue?
    let sections: [ResumeSection]
    
    init(
        id: String,
        title: String,
        subtitle: String,
        matchScore: Int,
        json: JSONValue?,
        sections: [ResumeSection] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.matchScore = matchScore
        self.json = json
        self.sections = sections
    }
}

