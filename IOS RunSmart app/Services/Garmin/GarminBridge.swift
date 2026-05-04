import Foundation
import AuthenticationServices
import Supabase
import UIKit

// MARK: - Garmin OAuth bridge

final class GarminBridge: NSObject {
    static let shared = GarminBridge()

    private let supabase = SupabaseManager.client
    private let garminGatewayURL = "https://runsmart-ai.com/garmin/connect"
    private var webAuthSession: ASWebAuthenticationSession?

    func connect() async throws {
        guard let token = try? await supabase.auth.session.accessToken else {
            throw GarminError.notAuthenticated
        }

        var components = URLComponents(string: garminGatewayURL)!
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        let startURL = components.url!

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: startURL,
                callbackURLScheme: "runsmart"
            ) { callbackURL, error in
                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let url = callbackURL,
                      url.host == "garmin",
                      url.path == "/connected" else {
                    continuation.resume()
                    return
                }
                continuation.resume()
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            session.start()
        }
    }

    func recentActivities(authUserID: UUID, limit: Int = 10) async -> [DBGarminActivity] {
        do {
            let rows: [DBGarminActivity] = try await supabase
                .from("garmin_activities_deduped")
                .select()
                .eq("auth_user_id", value: authUserID.uuidString)
                .order("start_time", ascending: false)
                .limit(limit)
                .execute()
                .value
            print("[GarminBridge] recentActivities deduped rows=\(rows.count)")
            return Self.uniqueActivities(rows)
        } catch {
            if !(error is CancellationError) {
                print("[GarminBridge] recentActivities deduped view error:", error)
            }
            return await recentActivitiesFromBaseTable(authUserID: authUserID, limit: limit)
        }
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

enum GarminError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Sign in before connecting Garmin."
        }
    }
}
