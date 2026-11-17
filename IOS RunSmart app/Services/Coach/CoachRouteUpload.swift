import Combine
import Foundation

/// Story 6.4 supplies a privacy-zone preparer and may enable this switch.
enum RouteUploadPolicy {
    static let isEnabled = false

    static func isEligible(run: RecordedRun, link: CoachLink, sharing: Bool) -> Bool {
        sharing && run.source == .runSmart && run.providerActivityID == nil &&
            run.startedAt > link.consentedAt && run.endedAt > run.startedAt && run.routePoints.count >= 2
    }
}

/// Web consumes a JSONB array of coordinate objects. No timestamps or telemetry.
struct CoachRouteCoordinate: Codable, Equatable {
    let lat: Double
    let lng: Double

    static let maxPoints = 512

    /// Encode already prepared points, retaining order and endpoints.
    static func encodePreparedPoints(_ points: [RunRoutePoint]) -> [Self]? {
        let valid = points.filter {
            $0.latitude.isFinite && $0.longitude.isFinite &&
                abs($0.latitude) <= 90 && abs($0.longitude) <= 180
        }
        guard valid.count >= 2 else { return nil }
        let count = min(maxPoints, valid.count)
        return (0..<count).map { index in
            let point = valid[index * (valid.count - 1) / (count - 1)]
            return Self(lat: (point.latitude * 100_000).rounded() / 100_000,
                        lng: (point.longitude * 100_000).rounded() / 100_000)
        }
    }
}

protocol RouteUploadPreparer {
    func prepare(_ points: [RunRoutePoint]) -> [CoachRouteCoordinate]?
}

struct DisabledRouteUploadPreparer: RouteUploadPreparer {
    func prepare(_ points: [RunRoutePoint]) -> [CoachRouteCoordinate]? { nil }
}

struct PendingCoachRoute: Codable, Equatable {
    let ownerID: UUID
    let linkID: UUID
    let runID: UUID
    let points: [CoachRouteCoordinate]
}

struct CoachRunRouteParams: Encodable {
    let item: PendingCoachRoute

    enum CodingKeys: String, CodingKey {
        case ownerID = "expected_owner_id"
        case linkID = "expected_link_id"
        case runID = "recorded_run_id"
        case points = "prepared_route"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(item.ownerID, forKey: .ownerID)
        try container.encode(item.linkID, forKey: .linkID)
        try container.encode(item.runID, forKey: .runID)
        try container.encode(item.points, forKey: .points)
    }
}

enum CoachRouteWriteResult: String, Decodable {
    case saved, missing, stopped
}

@MainActor
final class CoachRouteOutbox: ObservableObject {
    static let shared = CoachRouteOutbox()

    private let defaults: UserDefaults
    private let preparer: any RouteUploadPreparer
    private let enabled: Bool
    private let queueKey = "runsmart.coachRouteOutbox.v1"
    private var isFlushing = false
    @Published private(set) var preferences: [String: Bool]

    init(defaults: UserDefaults = .standard, enabled: Bool? = nil,
         preparer: (any RouteUploadPreparer)? = nil) {
        self.defaults = defaults
        self.enabled = enabled ?? RouteUploadPolicy.isEnabled
        self.preparer = preparer ?? DisabledRouteUploadPreparer()
        preferences = defaults.dictionary(forKey: "runsmart.coachRouteSharing.v1") as? [String: Bool] ?? [:]
    }

    private func key(_ ownerID: UUID, _ linkID: UUID) -> String {
        "\(ownerID.uuidString).\(linkID.uuidString)"
    }

    func sharing(ownerID: UUID, linkID: UUID) -> Bool {
        preferences[key(ownerID, linkID)] ?? true
    }

    func setSharing(_ sharing: Bool, ownerID: UUID, linkID: UUID) {
        preferences[key(ownerID, linkID)] = sharing
        defaults.set(preferences, forKey: "runsmart.coachRouteSharing.v1")
        if !sharing { discard(ownerID: ownerID, linkID: linkID) }
    }

    func discard(ownerID: UUID, linkID: UUID) {
        pending = pending.filter { $0.ownerID != ownerID || $0.linkID != linkID }
    }

    private(set) var pending: [PendingCoachRoute] {
        get {
            guard let data = defaults.data(forKey: queueKey) else { return [] }
            return (try? JSONDecoder().decode([PendingCoachRoute].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: queueKey) }
    }

    /// Call only with the fresh recorder result. Import/consolidation never stages routes.
    func stage(_ run: RecordedRun, ownerID: UUID, link: CoachLink, coachModeEnabled: Bool) {
        guard enabled, coachModeEnabled,
              RouteUploadPolicy.isEligible(run: run, link: link, sharing: sharing(ownerID: ownerID, linkID: link.id)),
              let points = preparer.prepare(run.routePoints), (2...CoachRouteCoordinate.maxPoints).contains(points.count)
        else { return }

        let item = PendingCoachRoute(ownerID: ownerID, linkID: link.id, runID: run.id, points: points)
        var queue = pending
        guard !queue.contains(where: { $0.ownerID == ownerID && $0.runID == run.id }) else { return }
        queue.append(item)
        pending = queue
    }

    func retry(ownerID: UUID, coachModeEnabled: Bool,
               canSend: (PendingCoachRoute) -> Bool,
               send: (PendingCoachRoute) async throws -> CoachRouteWriteResult) async {
        guard enabled, coachModeEnabled, !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        for item in pending where item.ownerID == ownerID {
            guard pending.contains(item), sharing(ownerID: ownerID, linkID: item.linkID), canSend(item) else { continue }
            do {
                let result = try await send(item)
                if result != .missing { pending = pending.filter { $0 != item } }
            } catch {
                // Keep the prepared route for the next sync or foreground.
            }
        }
    }
}
