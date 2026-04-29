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
    func send<Response: Decodable & Sendable>(_ endpoint: RunSmartAPI.Endpoint, as: Response.Type) async throws -> Response
}

struct URLSessionRunSmartAPIClient: RunSmartAPIClient {
    let baseURL: URL
    let session: URLSession
    var accessToken: String?

    init(baseURL: URL, session: URLSession = .shared, accessToken: String? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.accessToken = accessToken
    }

    func send<Response: Decodable & Sendable>(_ endpoint: RunSmartAPI.Endpoint, as: Response.Type) async throws -> Response {
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
            throw RunSmartAPIError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
