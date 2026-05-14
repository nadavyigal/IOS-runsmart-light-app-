import Foundation
import Supabase

// MARK: - Supabase Table Schema
//
// Run the following SQL in the Supabase dashboard (SQL Editor) to create the tables:
//
// -- user_saved_routes: persists each user's saved route library
// CREATE TABLE user_saved_routes (
//   id           UUID PRIMARY KEY NOT NULL,
//   user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
//   name         TEXT NOT NULL,
//   distance_meters  FLOAT8 NOT NULL,
//   elevation_gain_meters INT4 NOT NULL DEFAULT 0,
//   points_json  JSONB,        -- compact [[lat,lon,unix_ts,accuracy]], null if GPS storage disabled
//   source       TEXT NOT NULL, -- 'recorded' | 'garmin' | 'generated' | 'manual'
//   tags         TEXT[] NOT NULL DEFAULT '{}',
//   notes        TEXT NOT NULL DEFAULT '',
//   is_favorite  BOOL NOT NULL DEFAULT false,
//   created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
//   updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
// );
// ALTER TABLE user_saved_routes ENABLE ROW LEVEL SECURITY;
// CREATE POLICY "own rows" ON user_saved_routes USING (user_id = auth.uid());
//
// -- user_benchmark_routes: records which saved routes are designated benchmarks
// CREATE TABLE user_benchmark_routes (
//   id             UUID PRIMARY KEY NOT NULL,
//   user_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
//   saved_route_id UUID NOT NULL,
//   enabled_at     TIMESTAMPTZ NOT NULL DEFAULT now()
// );
// ALTER TABLE user_benchmark_routes ENABLE ROW LEVEL SECURITY;
// CREATE POLICY "own rows" ON user_benchmark_routes USING (user_id = auth.uid());
//
// Note: route match results are recomputed at runtime from stored runs + saved routes.
// GPS points are stored as compact arrays to minimise storage; users may opt out of
// GPS cloud storage in a future privacy settings panel.

// MARK: - Supabase row types

private struct SavedRouteRow: Codable, Sendable {
    var id: String
    var user_id: String
    var name: String
    var distance_meters: Double
    var elevation_gain_meters: Int
    var points_json: [[Double]]?  // [[lat, lon, unix_ts, accuracy]]
    var source: String
    var tags: [String]
    var notes: String
    var is_favorite: Bool
    var created_at: String
    var updated_at: String

    init(from route: SavedRoute, userID: UUID) {
        let iso = ISO8601DateFormatter()
        id = route.id.uuidString
        user_id = userID.uuidString
        name = route.name
        distance_meters = route.distanceMeters
        elevation_gain_meters = route.elevationGainMeters
        points_json = route.points.isEmpty ? nil : route.points.map { p in
            [p.latitude, p.longitude, p.timestamp.timeIntervalSince1970, p.horizontalAccuracy]
        }
        source = route.source.rawValue
        tags = route.tags
        notes = route.notes
        is_favorite = route.isFavorite
        created_at = iso.string(from: route.createdAt)
        updated_at = iso.string(from: route.updatedAt)
    }

    func toSavedRoute() -> SavedRoute? {
        guard let uuid = UUID(uuidString: id),
              let src = RouteSource(rawValue: source) else { return nil }
        let iso = ISO8601DateFormatter()
        let created = iso.date(from: created_at) ?? Date()
        let updated = iso.date(from: updated_at) ?? Date()
        let points: [RunRoutePoint] = (points_json ?? []).compactMap { arr in
            guard arr.count >= 2 else { return nil }
            return RunRoutePoint(
                latitude: arr[0],
                longitude: arr[1],
                timestamp: arr.count > 2 ? Date(timeIntervalSince1970: arr[2]) : Date(),
                horizontalAccuracy: arr.count > 3 ? arr[3] : 10,
                altitude: nil
            )
        }
        return SavedRoute(
            id: uuid, name: name,
            distanceMeters: distance_meters,
            elevationGainMeters: elevation_gain_meters,
            points: points, source: src, tags: tags, notes: notes,
            isFavorite: is_favorite, createdAt: created, updatedAt: updated
        )
    }
}

private struct BenchmarkEntryRow: Codable, Sendable {
    var id: String
    var user_id: String
    var saved_route_id: String
    var enabled_at: String

    init(id: UUID, savedRouteID: UUID, enabledAt: Date, userID: UUID) {
        self.id = id.uuidString
        user_id = userID.uuidString
        saved_route_id = savedRouteID.uuidString
        enabled_at = ISO8601DateFormatter().string(from: enabledAt)
    }
}

// MARK: - Protocol for testability

protocol RouteRemoteStoring {
    func fetchSavedRoutes(userID: UUID) async throws -> [SavedRoute]
    func upsertRoute(_ route: SavedRoute, userID: UUID) async throws
    func deleteRoute(id: UUID, userID: UUID) async throws
    func fetchBenchmarkEntries(userID: UUID) async throws -> [(id: UUID, savedRouteID: UUID, enabledAt: Date)]
    func upsertBenchmark(id: UUID, savedRouteID: UUID, enabledAt: Date, userID: UUID) async throws
    func deleteBenchmark(savedRouteID: UUID, userID: UUID) async throws
}

// MARK: - Supabase implementation

struct SupabaseRouteRemoteStore: RouteRemoteStoring {
    private let client = SupabaseManager.client

    func fetchSavedRoutes(userID: UUID) async throws -> [SavedRoute] {
        let rows: [SavedRouteRow] = try await client
            .from("user_saved_routes")
            .select()
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        return rows.compactMap { $0.toSavedRoute() }
    }

    func upsertRoute(_ route: SavedRoute, userID: UUID) async throws {
        let row = SavedRouteRow(from: route, userID: userID)
        try await client
            .from("user_saved_routes")
            .upsert(row)
            .execute()
    }

    func deleteRoute(id: UUID, userID: UUID) async throws {
        try await client
            .from("user_saved_routes")
            .delete()
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userID.uuidString)
            .execute()
    }

    func fetchBenchmarkEntries(userID: UUID) async throws -> [(id: UUID, savedRouteID: UUID, enabledAt: Date)] {
        let rows: [BenchmarkEntryRow] = try await client
            .from("user_benchmark_routes")
            .select()
            .eq("user_id", value: userID.uuidString)
            .execute()
            .value
        let iso = ISO8601DateFormatter()
        return rows.compactMap { row in
            guard let id = UUID(uuidString: row.id),
                  let sid = UUID(uuidString: row.saved_route_id),
                  let date = iso.date(from: row.enabled_at) else { return nil }
            return (id: id, savedRouteID: sid, enabledAt: date)
        }
    }

    func upsertBenchmark(id: UUID, savedRouteID: UUID, enabledAt: Date, userID: UUID) async throws {
        let row = BenchmarkEntryRow(id: id, savedRouteID: savedRouteID, enabledAt: enabledAt, userID: userID)
        try await client
            .from("user_benchmark_routes")
            .upsert(row)
            .execute()
    }

    func deleteBenchmark(savedRouteID: UUID, userID: UUID) async throws {
        try await client
            .from("user_benchmark_routes")
            .delete()
            .eq("saved_route_id", value: savedRouteID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .execute()
    }
}

// MARK: - Pure merge logic (testable)

enum RouteSync {
    /// Merges remote and local saved routes. Remote wins on ID conflict; local-only routes are kept.
    static func merge(remote: [SavedRoute], local: [SavedRoute]) -> [SavedRoute] {
        if remote.isEmpty { return local }
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { _, r in r })
        for route in remote { byID[route.id] = route }
        return byID.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Merges remote benchmark entries with locally stored BenchmarkRoutes.
    /// Remote entries win for unknown savedRouteIDs; local cached stats are preserved for known ones.
    static func mergeBenchmarks(
        remoteEntries: [(id: UUID, savedRouteID: UUID, enabledAt: Date)],
        local: [BenchmarkRoute]
    ) -> [BenchmarkRoute] {
        if remoteEntries.isEmpty { return local }
        var byRouteID = Dictionary(local.map { ($0.savedRouteID, $0) }, uniquingKeysWith: { _, r in r })
        for entry in remoteEntries where byRouteID[entry.savedRouteID] == nil {
            byRouteID[entry.savedRouteID] = BenchmarkRoute(
                id: entry.id,
                savedRouteID: entry.savedRouteID,
                enabledAt: entry.enabledAt,
                historicalRunCount: 0,
                personalBestSeconds: nil,
                personalBestDate: nil,
                averagePaceSecondsPerKm: nil,
                averageDurationSeconds: nil
            )
        }
        return byRouteID.values.sorted { $0.enabledAt < $1.enabledAt }
    }
}
