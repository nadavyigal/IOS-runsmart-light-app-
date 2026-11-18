import Combine
import Foundation
import Supabase

// Story 6.2. A coach reads a linked athlete's run map only through
// `coach_get_run_route`, which checks an active link like Story 2.2's reads.

/// What the coach may see of one run's route. Only `map` carries points.
enum CoachRunRouteState: Equatable {
    case map([CoachRouteCoordinate])
    /// The athlete hid this run's map (Story 6.3). The run summary stays visible.
    case hidden
    /// The route was too short to share after privacy trimming (Story 6.4).
    case routeHidden
    /// No route, sharing was off, or a route that arrived another way. Never an error.
    case noMap

    var copy: String? {
        switch self {
        case .map: nil
        case .hidden: "Map hidden"
        case .routeHidden: "Route hidden"
        case .noMap: "No map"
        }
    }
}

nonisolated struct CoachRunRouteRow: Decodable, Sendable {
    let state: String
    let route: [CoachRouteCoordinate]?
}

nonisolated protocol CoachRunRouteFetching: Sendable {
    /// Nil when the server returns no row: a revoked or missing link, or an unknown run.
    func route(runID: Int) async throws -> CoachRunRouteRow?
}

private nonisolated struct CoachGetRunRouteParams: Encodable, Sendable {
    let p_run: Int
}

nonisolated struct SupabaseCoachRunRouteService: CoachRunRouteFetching {
    func route(runID: Int) async throws -> CoachRunRouteRow? {
        let rows: [CoachRunRouteRow] = try await SupabaseManager.client
            .rpc("coach_get_run_route", params: CoachGetRunRouteParams(p_run: runID))
            .execute()
            .value
        return rows.first
    }
}

nonisolated final class MockCoachRunRouteService: CoachRunRouteFetching, @unchecked Sendable {
    var rows: [Int: CoachRunRouteRow] = [:]
    var failure: Error?
    private(set) var calls = 0

    func route(runID: Int) async throws -> CoachRunRouteRow? {
        calls += 1
        if let failure { throw failure }
        return rows[runID]
    }
}

enum CoachRunRouteMapping {
    /// Unknown states fall back to "No map", which reveals nothing.
    static func state(_ row: CoachRunRouteRow) -> CoachRunRouteState {
        switch row.state {
        case "map":
            guard let route = row.route, route.count >= 2 else { return .noMap }
            return .map(route)
        case "hidden": return .hidden
        case "route_hidden": return .routeHidden
        default: return .noMap
        }
    }

    /// RouteMapView draws `RunRoutePoint`s. A coach route has no times or accuracy.
    static func points(_ route: [CoachRouteCoordinate]) -> [RunRoutePoint] {
        route.map {
            RunRoutePoint(latitude: $0.lat, longitude: $0.lng, timestamp: .distantPast, horizontalAccuracy: 0, altitude: nil)
        }
    }

    /// "Route map for Saturday's run, 8.2 kilometres".
    static func altText(completedAt: Date, distanceKm: Double, calendar: Calendar, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        let km = distanceKm.rounded() == distanceKm ? String(Int(distanceKm)) : String(format: "%.1f", distanceKm)
        return "Route map for \(formatter.string(from: completedAt))'s run, \(km) kilometres"
    }

    static let caption = "Start/end hidden for privacy"
    static let loadFailed = "Couldn't load the map."
}

@MainActor
final class CoachRunMapModel: ObservableObject {
    enum Phase: Equatable { case loading, loaded(CoachRunRouteState), failed, revoked }

    @Published private(set) var phase: Phase = .loading
    let runID: Int
    private let service: any CoachRunRouteFetching

    init(runID: Int, service: any CoachRunRouteFetching = SupabaseCoachRunRouteService()) {
        self.runID = runID
        self.service = service
    }

    func load() async {
        phase = .loading
        do {
            guard let row = try await service.route(runID: runID) else {
                phase = .revoked
                return
            }
            phase = .loaded(CoachRunRouteMapping.state(row))
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            phase = .failed
        }
    }
}
