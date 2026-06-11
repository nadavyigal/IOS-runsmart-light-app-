import Foundation
import AuthenticationServices
import Supabase
import UIKit

// MARK: - Garmin OAuth bridge

final class GarminBridge: NSObject {
    static let shared = GarminBridge()

    private static let callbackURLScheme = "runsmart"
    private static let redirectURI = "runsmart://garmin/callback"

    private let supabase = SupabaseManager.client
    private var webAuthSession: ASWebAuthenticationSession?

    // Short-lived cache so rapid concurrent calls within one loadData() cycle
    // reuse the same Supabase result instead of firing N parallel queries.
    private var activityCache: [UUID: (rows: [DBGarminActivity], expiry: Date)] = [:]
    private static let cacheTTL: TimeInterval = 60

    private var garminGatewayURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "RUNSMART_GARMIN_GATEWAY_URL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://www.runsmart-ai.com/api/devices/garmin/connect")!
    }

    func connect() async throws {
        guard let session = try? await supabase.auth.session, !session.isExpired else {
            throw GarminError.notAuthenticated
        }

        guard let numericUserID = try await garminUserID(authUserID: session.user.id) else {
            throw GarminError.missingProfile
        }

        let startURL = try await garminAuthorizationURL(
            userID: numericUserID,
            accessToken: session.accessToken
        )

        let authUserID = session.user.id
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(
                url: startURL,
                callbackURLScheme: Self.callbackURLScheme
            ) { callbackURL, error in
                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: GarminError.canceled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                if let url = callbackURL, !Self.isGarminCallback(url) {
                    print("[GarminBridge] connect ignored unexpected callback url=\(url.absoluteString)")
                }
                continuation.resume()
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            session.start()
        }

        try await waitForConnectedAccount(authUserID: authUserID)
    }

    private static func isGarminCallback(_ url: URL) -> Bool {
        if url.scheme?.caseInsensitiveCompare(callbackURLScheme) == .orderedSame {
            return url.host == "garmin" || url.path.hasSuffix("/garmin/callback")
        }
        return url.host?.contains("runsmart-ai.com") == true
            && (url.path.hasSuffix("/garmin/callback") || url.query?.contains("screen=profile") == true)
    }

    private func waitForConnectedAccount(authUserID: UUID, attempts: Int = 12) async throws {
        for attempt in 0..<attempts {
            if let connection = await connectionStatus(authUserID: authUserID),
               connection.status == "connected" {
                invalidateActivityCache()
                print("[GarminBridge] connect confirmed status=connected attempt=\(attempt + 1)")
                return
            }
            if attempt < attempts - 1 {
                try await Task.sleep(nanoseconds: 750_000_000)
            }
        }
        throw GarminError.notConnected
    }

    private func garminUserID(authUserID: UUID) async throws -> Int? {
        let rows: [GarminProfileIdentity] = try await supabase
            .from("profiles")
            .select("id,auth_user_id")
            .eq("auth_user_id", value: authUserID.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first?.numericUserID
    }

    private func garminAuthorizationURL(userID: Int, accessToken: String) async throws -> URL {
        var request = URLRequest(url: garminGatewayURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let redirectURI = Self.redirectURI
        request.httpBody = try JSONEncoder().encode(GarminConnectRequest(userID: userID, redirectURI: redirectURI))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GarminError.gatewayFailed("Garmin gateway did not return a valid response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GarminError.gatewayFailed(message?.isEmpty == false ? message! : "Garmin gateway returned \(http.statusCode).")
        }

        let payload = try JSONDecoder().decode(GarminConnectResponse.self, from: data)
        guard payload.success, let authURL = payload.authURL, let url = URL(string: authURL) else {
            throw GarminError.gatewayFailed(payload.error ?? "Garmin gateway did not return an authorization URL.")
        }
        return url
    }

    func recentActivities(authUserID: UUID, limit: Int = 10) async -> [DBGarminActivity] {
        // Serve from cache when fresh — prevents N concurrent queries per loadData() cycle.
        if let cached = activityCache[authUserID], Date() < cached.expiry {
            return Array(Self.uniqueActivities(cached.rows).prefix(limit))
        }

        do {
            let fetchLimit = max(limit, 30) // cache a generous slice to serve all callers
            let rows: [DBGarminActivity] = try await supabase
                .from("garmin_activities_deduped")
                .select()
                .eq("auth_user_id", value: authUserID.uuidString)
                .order("start_time", ascending: false)
                .limit(fetchLimit)
                .execute()
                .value
            print("[GarminBridge] recentActivities deduped rows=\(rows.count)")
            activityCache[authUserID] = (rows: rows, expiry: Date().addingTimeInterval(Self.cacheTTL))
            return Array(Self.uniqueActivities(rows).prefix(limit))
        } catch {
            if !(error is CancellationError) {
                print("[GarminBridge] recentActivities deduped view error:", error)
            }
            return await recentActivitiesFromBaseTable(authUserID: authUserID, limit: limit)
        }
    }

    func invalidateActivityCache() {
        activityCache.removeAll()
    }

    func latestDailyMetrics(authUserID: UUID) async -> DBGarminDailyMetrics? {
        do {
            let rows: [DBGarminDailyMetrics] = try await supabase
                .from("garmin_daily_metrics_deduped")
                .select()
                .eq("auth_user_id", value: authUserID.uuidString)
                .order("date", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            if !(error is CancellationError) {
                print("[GarminBridge] latestDailyMetrics deduped view error:", error)
            }
            return await latestDailyMetricsFromBaseTable(authUserID: authUserID)
        }
    }

    func dailyMetrics(authUserID: UUID, lastDays: Int) async -> [DBGarminDailyMetrics] {
        let limit = max(1, lastDays)
        do {
            let rows: [DBGarminDailyMetrics] = try await supabase
                .from("garmin_daily_metrics_deduped")
                .select()
                .eq("auth_user_id", value: authUserID.uuidString)
                .order("date", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows.sorted(by: { $0.date < $1.date })
        } catch {
            if !(error is CancellationError) {
                print("[GarminBridge] dailyMetrics deduped view error:", error)
            }
            return await dailyMetricsFromBaseTable(authUserID: authUserID, lastDays: limit)
        }
    }

    private func recentActivitiesFromBaseTable(authUserID: UUID, limit: Int) async -> [DBGarminActivity] {
        do {
            let rows: [DBGarminActivity] = try await supabase
                .from("garmin_activities")
                .select()
                .eq("auth_user_id", value: authUserID.uuidString)
                .order("start_time", ascending: false)
                .limit(limit * 3)
                .execute()
                .value
            let unique = Self.uniqueActivities(rows)
            print("[GarminBridge] recentActivities base fallback rows=\(rows.count) unique=\(unique.count)")
            return Array(unique.prefix(limit))
        } catch {
            if !(error is CancellationError) {
                print("[GarminBridge] recentActivities base fallback error:", error)
            }
            return []
        }
    }

    private func latestDailyMetricsFromBaseTable(authUserID: UUID) async -> DBGarminDailyMetrics? {
        do {
            let rows: [DBGarminDailyMetrics] = try await supabase
                .from("garmin_daily_metrics")
                .select()
                .eq("auth_user_id", value: authUserID.uuidString)
                .order("date", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch {
            if !(error is CancellationError) {
                print("[GarminBridge] latestDailyMetrics base fallback error:", error)
            }
            return nil
        }
    }

    private func dailyMetricsFromBaseTable(authUserID: UUID, lastDays: Int) async -> [DBGarminDailyMetrics] {
        do {
            let rows: [DBGarminDailyMetrics] = try await supabase
                .from("garmin_daily_metrics")
                .select()
                .eq("auth_user_id", value: authUserID.uuidString)
                .order("date", ascending: false)
                .limit(lastDays)
                .execute()
                .value
            return rows.sorted(by: { $0.date < $1.date })
        } catch {
            if !(error is CancellationError) {
                print("[GarminBridge] dailyMetrics base fallback error:", error)
            }
            return []
        }
    }

    func activityRoutePoints(activityID: String) async -> [RunRoutePoint] {
        do {
            let rows: [DBGarminActivityPoint] = try await supabase
                .from("garmin_activity_points")
                .select()
                .eq("activity_id", value: activityID)
                .order("sequence", ascending: true)
                .execute()
                .value

            return rows.enumerated().map { index, row in
                RunRoutePoint(
                    latitude: row.latitude,
                    longitude: row.longitude,
                    timestamp: row.timestamp.flatMap(Self.parseISO8601) ?? Date().addingTimeInterval(Double(index)),
                    horizontalAccuracy: row.horizontalAccuracy ?? 0,
                    altitude: row.altitude
                )
            }
        } catch {
            if !(error is CancellationError) {
                print("[GarminBridge] activityRoutePoints error:", error)
            }
            return []
        }
    }

    func connectionStatus(authUserID: UUID) async -> DBGarminConnection? {
        do {
            let rows: [DBGarminConnection] = try await supabase
                .from("garmin_connections")
                .select()
                .eq("auth_user_id", value: authUserID.uuidString)
                .limit(1)
                .execute()
                .value
            return rows.first
        } catch { return nil }
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func uniqueActivities(_ rows: [DBGarminActivity]) -> [DBGarminActivity] {
        var seen = Set<String>()
        return rows.filter { activity in
            guard !seen.contains(activity.activityId) else { return false }
            seen.insert(activity.activityId)
            return true
        }
    }
}

private struct DBGarminActivityPoint: Codable {
    let activityId: String
    let sequence: Int?
    let latitude: Double
    let longitude: Double
    let timestamp: String?
    let horizontalAccuracy: Double?
    let altitude: Double?

    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case sequence
        case latitude
        case longitude
        case timestamp
        case horizontalAccuracy = "horizontal_accuracy"
        case altitude
    }
}

extension GarminBridge: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .keyWindow ?? UIWindow()
    }
}

private struct GarminConnectRequest: Encodable {
    let userID: Int
    let redirectURI: String

    enum CodingKeys: String, CodingKey {
        case userID = "userId"
        case redirectURI = "redirectUri"
    }
}

private struct GarminConnectResponse: Decodable {
    let success: Bool
    let authURL: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case authURL = "authUrl"
        case error
    }
}

private struct GarminProfileIdentity: Decodable {
    let numericUserID: Int?

    enum CodingKeys: String, CodingKey {
        case id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let int = try? c.decode(Int.self, forKey: .id) {
            numericUserID = int
        } else if let string = try? c.decode(String.self, forKey: .id), let int = Int(string) {
            numericUserID = int
        } else {
            numericUserID = nil
        }
    }
}

enum GarminError: LocalizedError {
    case notAuthenticated
    case missingProfile
    case canceled
    case notConnected
    case gatewayFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Sign in before connecting Garmin."
        case .missingProfile: "Finish RunSmart onboarding before connecting Garmin."
        case .canceled: "Garmin connection was canceled."
        case .notConnected: "Garmin authorization finished in the browser, but RunSmart has not received a connected account yet. Return to the app and tap Connect again."
        case .gatewayFailed(let message): message
        }
    }
}
