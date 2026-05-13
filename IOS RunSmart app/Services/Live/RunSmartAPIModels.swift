import Foundation

enum RunSmartDTO {
    struct AuthSession: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAtISO8601: String
        let tokenType: String
        let user: UserProfile
    }

    struct UserProfile: Codable {
        let userID: String
        let displayName: String
        let email: String?
        let goal: String
        let level: String
        let streakLabel: String
        let stats: UserStats
    }

    struct UserStats: Codable {
        let totalRuns: Int
        let totalDistanceKm: Int
        let totalTimeLabel: String
    }

    struct TodayPayload: Codable {
        let readinessScore: Int
        let readinessLabel: String
        let workoutTitle: String
        let plannedDistanceLabel: String
        let targetPaceLabel: String
        let elevationLabel: String
        let coachMessage: String
    }

    struct PlanPayload: Codable {
        let weekStartISO8601: String
        let weekEndISO8601: String
        let workouts: [WorkoutItem]
    }

    struct WorkoutItem: Codable {
        let workoutID: String
        let weekday: String
        let dateLabel: String
        let kind: String
        let title: String
        let distanceLabel: String
        let detailLabel: String
        let isToday: Bool
        let isComplete: Bool
    }

    struct CoachConversationPayload: Codable {
        let threadID: String
        let messages: [CoachChatMessage]
    }

    struct CoachChatMessage: Codable {
        let messageID: String
        let text: String
        let timeLabel: String
        let role: String
    }

    struct SendCoachMessageRequest: Codable {
        let threadID: String?
        let text: String
    }

    struct RunLogRequest: Codable {
        let startedAtISO8601: String
        let endedAtISO8601: String
        let distanceMeters: Double
        let movingTimeSeconds: Int
        let averagePaceSecondsPerKm: Double
        let averageHeartRateBPM: Int?
        let routePoints: [RoutePoint]
    }

    struct RunLogResponse: Codable {
        let runID: String
        let savedAtISO8601: String
    }

    struct CurrentRunMetricsPayload: Codable {
        let distanceKm: String
        let pacePerKm: String
        let elapsedTime: String
        let heartRateBPM: String
    }

    struct RouteSuggestionPayload: Codable {
        let routeID: String
        let name: String
        let distanceKm: Double
        let elevationGainMeters: Int
        let estimatedDurationMinutes: Int
        let points: [RoutePoint]
    }

    struct RoutePoint: Codable {
        let latitude: Double
        let longitude: Double
        let sequence: Int
    }

    struct UserPreferencesPayload: Codable {
        let units: String
        let weekStartsOn: String
        let defaultCoachTone: String
        let trainingDays: [String]
        let notificationEnabled: Bool
    }

    struct ReminderPayload: Codable {
        let reminderID: String
        let type: String
        let title: String
        let body: String
        let localTime: String
        let enabled: Bool
    }

    struct DeviceSyncPayload: Codable {
        let provider: String
        let connectionState: String
        let lastSuccessfulSyncISO8601: String?
        let permissions: [String]
    }

    struct RunReportRequest: Codable {
        let run: WebRun
        let gps: GPSContext?
        let paceData: [PacePoint]?
        let upcomingWorkouts: [WorkoutReportContext]?
        let historicalContext: HistoricalContext?

        struct WebRun: Codable {
            let id: String
            let type: String
            let distanceKm: Double
            let durationSeconds: Int
            let avgPaceSecondsPerKm: Double?
            let completedAt: String
            let notes: String?
            let heartRateBpm: Int?
        }

        struct GPSContext: Codable {
            let points: Int
            let startAccuracy: Double?
            let endAccuracy: Double?
            let averageAccuracy: Double?
        }

        struct PacePoint: Codable {
            let distanceKm: Double
            let paceMinPerKm: Double
            let timestamp: Double?
        }

        struct HistoricalContext: Codable {
            let recentRuns: [HistoricalRun]
            let weeklyVolume7d: Double
            let weeklyVolume28d: Double
            let weeklyRunCount7d: Int
            let recoveryScore: Int?
            let readinessScore: Int?
        }

        struct HistoricalRun: Codable {
            let type: String
            let distanceKm: Double
            let paceSecPerKm: Double?
            let date: String
            let effort: String?
        }
    }

    struct WorkoutReportContext: Codable {
        let date: String?
        let sessionType: String?
        let durationMinutes: Int?
        let targetPace: String?
        let targetHrZone: String?
        let notes: String?
        let tags: [String]?
        let workoutID: String?
        let scheduledDateISO8601: String?
        let title: String
        let distanceLabel: String?
        let targetPaceSecondsPerKm: Int?
    }

    struct RunReportResponse: Decodable {
        let report: RunReportPayload
        let source: String
    }

    struct RunReportPayload: Decodable, Sendable {
        let summary: String?
        let effort: String?
        let recovery: String?
        let nextSessionNudge: String?
        let coachScore: Int?
        let structuredNextWorkout: StructuredNextWorkout?
        let keyInsights: [String]?
        let pacing: String?
        let biomechanics: String?
        let recoveryTimeline: [String]?

        enum CodingKeys: String, CodingKey {
            case summary, effort, recovery, nextSessionNudge, coachScore, structuredNextWorkout
            case keyInsights, insights, pacing, pacingAnalysis, biomechanics, biomechanicalAnalysis, detailedRecovery
        }

        enum ScoreKeys: String, CodingKey {
            case overall
        }

        enum RecoveryKeys: String, CodingKey {
            case priority, optional
            case next24h, immediate, next2h, next48h
        }

        enum WorkoutKeys: String, CodingKey {
            case title, dateLabel, distance, target, notes
            case sessionType, main, targetEffort, coachingCue, totalDurationMin
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)

            if let text = try? c.decodeIfPresent(String.self, forKey: .summary) {
                summary = text
            } else if let lines = try? c.decodeIfPresent([String].self, forKey: .summary) {
                summary = lines.joined(separator: " ")
            } else {
                summary = nil
            }

            effort = try? c.decodeIfPresent(String.self, forKey: .effort)
            nextSessionNudge = try? c.decodeIfPresent(String.self, forKey: .nextSessionNudge)
            keyInsights = Self.stringList(from: c, preferred: .keyInsights, fallback: .insights)
            pacing = (try? c.decodeIfPresent(String.self, forKey: .pacing)) ??
                (try? c.decodeIfPresent(String.self, forKey: .pacingAnalysis))
            biomechanics = (try? c.decodeIfPresent(String.self, forKey: .biomechanics)) ??
                (try? c.decodeIfPresent(String.self, forKey: .biomechanicalAnalysis))

            if let recoveryText = try? c.decodeIfPresent(String.self, forKey: .recovery) {
                recovery = recoveryText
                recoveryTimeline = nil
            } else if let nested = try? c.nestedContainer(keyedBy: RecoveryKeys.self, forKey: .recovery) {
                let priority = (try? nested.decodeIfPresent([String].self, forKey: .priority)) ?? []
                let optional = (try? nested.decodeIfPresent([String].self, forKey: .optional)) ?? []
                recovery = (priority + optional).joined(separator: " ")
                recoveryTimeline = priority + optional
            } else if let detailed = try? c.nestedContainer(keyedBy: RecoveryKeys.self, forKey: .detailedRecovery) {
                let values = [
                    try? detailed.decodeIfPresent(String.self, forKey: .immediate),
                    try? detailed.decodeIfPresent(String.self, forKey: .next2h),
                    try? detailed.decodeIfPresent(String.self, forKey: .next24h),
                    try? detailed.decodeIfPresent(String.self, forKey: .next48h)
                ].compactMap { $0 }
                recovery = values.joined(separator: " ")
                recoveryTimeline = values
            } else {
                recovery = nil
                recoveryTimeline = nil
            }

            if let score = try? c.decodeIfPresent(Int.self, forKey: .coachScore) {
                coachScore = score
            } else if let scoreContainer = try? c.nestedContainer(keyedBy: ScoreKeys.self, forKey: .coachScore) {
                coachScore = try? scoreContainer.decodeIfPresent(Int.self, forKey: .overall)
            } else {
                coachScore = nil
            }

            if let next = try? c.decodeIfPresent(StructuredNextWorkout.self, forKey: .structuredNextWorkout) {
                structuredNextWorkout = next
            } else if let nested = try? c.nestedContainer(keyedBy: WorkoutKeys.self, forKey: .structuredNextWorkout) {
                let sessionType = (try? nested.decodeIfPresent(String.self, forKey: .sessionType)) ?? "Next Workout"
                let main = try? nested.decodeIfPresent(String.self, forKey: .main)
                let target = (try? nested.decodeIfPresent(String.self, forKey: .target)) ??
                    (try? nested.decodeIfPresent(String.self, forKey: .targetEffort))
                let cue = try? nested.decodeIfPresent(String.self, forKey: .coachingCue)
                structuredNextWorkout = StructuredNextWorkout(
                    title: sessionType,
                    dateLabel: try? nested.decodeIfPresent(String.self, forKey: .dateLabel),
                    distance: try? nested.decodeIfPresent(String.self, forKey: .distance),
                    target: target,
                    notes: [main, cue].compactMap { $0 }.joined(separator: " ")
                )
            } else {
                structuredNextWorkout = nil
            }
        }

        private static func stringList(from c: KeyedDecodingContainer<CodingKeys>, preferred: CodingKeys, fallback: CodingKeys) -> [String]? {
            if let values = try? c.decodeIfPresent([String].self, forKey: preferred) {
                return values
            }
            if let value = try? c.decodeIfPresent(String.self, forKey: preferred) {
                return [value]
            }
            if let values = try? c.decodeIfPresent([String].self, forKey: fallback) {
                return values
            }
            if let value = try? c.decodeIfPresent(String.self, forKey: fallback) {
                return [value]
            }
            return nil
        }
    }

    struct GeneratePlanRequest: Encodable {
        let userContext: UserContext
        let trainingHistory: TrainingHistory?
        let goals: GoalsContext?
        let challenge: Challenge?
        let targetDistance: String?
        let totalWeeks: Int?
        let planPreferences: PlanPreferences

        struct UserContext: Encodable {
            let userId: Int?
            let goal: String
            let experience: String
            let age: Int?
            let daysPerWeek: Int
            let preferredTimes: [String]
            let coachingStyle: String?
            let averageWeeklyKm: Double?
            let trainingDataSource: String?
        }

        struct TrainingHistory: Encodable {
            let weeklyVolumeKm: Double
            let consistencyScore: Int
            let recentRuns: [RecentRun]
        }

        struct RecentRun: Encodable {
            let date: String
            let distanceKm: Double
            let durationMinutes: Int
            let avgPace: String?
            let rpe: Int?
            let notes: String?
        }

        struct GoalsContext: Encodable {
            let primaryGoal: PrimaryGoal

            struct PrimaryGoal: Encodable {
                let title: String
                let goalType: String
                let category: String
                let target: String
                let deadline: String
                let progressPercentage: Int
            }
        }

        struct Challenge: Encodable {
            let slug: String?
            let name: String
            let category: String
            let difficulty: String?
            let durationDays: Int
            let workoutPattern: String?
            let coachTone: String?
            let targetAudience: String?
            let promise: String?
        }

        struct PlanPreferences: Encodable {
            let trainingDays: [String]
            let availableDays: [String]
            let longRunDay: String?
            let trainingVolume: String
            let difficulty: String
        }
    }

    struct GeneratePlanResponse: Decodable {
        let plan: GeneratedPlan?
        let source: String?
        let error: String?
    }

    struct GeneratedPlan: Decodable {
        let title: String
        let description: String?
        let totalWeeks: Int
        let targetDistance: Double?
        let targetTime: Int?
        let peakWeeklyVolume: Double?
        let workouts: [GeneratedWorkout]
    }

    struct GeneratedWorkout: Decodable {
        let week: Int
        let day: String
        let type: String
        let distance: Double
        let duration: Int?
        let notes: String?
        let pace: Int?
        let intensity: String?
        let trainingPhase: String?
        let workoutStructure: String?

        enum CodingKeys: String, CodingKey {
            case week, day, type, distance, duration, notes, pace, intensity
            case trainingPhase, phase
            case workoutStructure, structure
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            week = (try? c.decode(Int.self, forKey: .week)) ?? 1
            day = (try? c.decode(String.self, forKey: .day)) ?? "Mon"
            type = (try? c.decode(String.self, forKey: .type)) ?? "easy"
            distance = (try? c.decode(Double.self, forKey: .distance)) ?? 0
            duration = try? c.decodeIfPresent(Int.self, forKey: .duration)
            notes = try? c.decodeIfPresent(String.self, forKey: .notes)
            pace = try? c.decodeIfPresent(Int.self, forKey: .pace)
            intensity = try? c.decodeIfPresent(String.self, forKey: .intensity)
            trainingPhase = (try? c.decodeIfPresent(String.self, forKey: .trainingPhase)) ??
                (try? c.decodeIfPresent(String.self, forKey: .phase))
            if let string = try? c.decodeIfPresent(String.self, forKey: .workoutStructure) {
                workoutStructure = string
            } else if let string = try? c.decodeIfPresent(String.self, forKey: .structure) {
                workoutStructure = string
            } else if let raw = try? c.decodeIfPresent(JSONValue.self, forKey: .workoutStructure) {
                workoutStructure = raw.jsonString
            } else if let raw = try? c.decodeIfPresent(JSONValue.self, forKey: .structure) {
                workoutStructure = raw.jsonString
            } else {
                workoutStructure = nil
            }
        }
    }

    enum JSONValue: Decodable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case object([String: JSONValue])
        case array([JSONValue])
        case null

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() {
                self = .null
            } else if let value = try? c.decode(String.self) {
                self = .string(value)
            } else if let value = try? c.decode(Double.self) {
                self = .number(value)
            } else if let value = try? c.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? c.decode([String: JSONValue].self) {
                self = .object(value)
            } else {
                self = .array((try? c.decode([JSONValue].self)) ?? [])
            }
        }

        var jsonString: String? {
            guard let data = try? JSONEncoder().encode(encodableValue),
                  let string = String(data: data, encoding: .utf8) else {
                return nil
            }
            return string
        }

        private var encodableValue: AnyEncodable {
            switch self {
            case .string(let value): AnyEncodable(value)
            case .number(let value): AnyEncodable(value)
            case .bool(let value): AnyEncodable(value)
            case .object(let value): AnyEncodable(value.mapValues(\.encodableValue))
            case .array(let value): AnyEncodable(value.map(\.encodableValue))
            case .null: AnyEncodable(Optional<String>.none)
            }
        }
    }

    struct AnyEncodable: Encodable {
        private let encodeBlock: (Encoder) throws -> Void

        init<T: Encodable>(_ value: T) {
            encodeBlock = value.encode(to:)
        }

        func encode(to encoder: Encoder) throws {
            try encodeBlock(encoder)
        }
    }
}

enum RunSmartAPI {
    enum Method: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    struct Endpoint {
        let path: String
        let method: Method
        let queryItems: [URLQueryItem]
        let body: Data?

        init(path: String, method: Method, queryItems: [URLQueryItem] = [], body: Data? = nil) {
            self.path = path
            self.method = method
            self.queryItems = queryItems
            self.body = body
        }
    }
}

enum RunSmartAPIError: Error {
    case invalidURL
    case badStatus(Int)
}

protocol RunSmartAPIClient {
    nonisolated func send<Response: Decodable>(_ endpoint: RunSmartAPI.Endpoint, as: Response.Type) async throws -> Response
}

struct URLSessionRunSmartAPIClient: RunSmartAPIClient {
    let baseURL: URL
    let session: URLSession
    var accessToken: String?

    init(baseURL: URL = URLSessionRunSmartAPIClient.configuredBaseURL(), session: URLSession = .shared, accessToken: String? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.accessToken = accessToken
    }

    nonisolated func send<Response: Decodable>(_ endpoint: RunSmartAPI.Endpoint, as: Response.Type) async throws -> Response {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false)
        components?.queryItems = endpoint.queryItems.isEmpty ? nil : endpoint.queryItems

        guard let url = components?.url else {
            throw RunSmartAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if let decoded = try? JSONDecoder().decode(Response.self, from: data) {
                return decoded
            }
            throw RunSmartAPIError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    static func configuredBaseURL() -> URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "RunSmartAPIBaseURL") as? String,
           let url = URL(string: raw),
           !raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            return url
        }
        return URL(string: "https://runsmart-ai.com")!
    }
}
