import Combine
import Foundation

/// Story 6.4 turns this on. Release still uploads nothing: staging also requires
/// `RunSmartFeatures.coachModeEnabled`, which is false outside a debug coach-mode launch.
enum RouteUploadPolicy {
    static let isEnabled = true

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

enum CoachRouteVisibility: String, Codable, Equatable {
    case shared
    case tooShort = "too_short"
}

/// Prepared coach upload. `points` is empty when the route must not be uploaded.
struct RouteUploadPreparation: Equatable {
    let points: [CoachRouteCoordinate]
    let radiusMeters: Double

    var status: CoachRouteVisibility {
        (2...CoachRouteCoordinate.maxPoints).contains(points.count) ? .shared : .tooShort
    }
}

protocol RouteUploadPreparer {
    /// Work from a copy of `points`. `distanceMeters` is the run's recorded distance.
    func prepare(_ points: [RunRoutePoint], distanceMeters: Double) -> RouteUploadPreparation
}

/// Drops a 200–300 m disk around the start and the finish, then encodes with the 6.1 encoder.
struct PrivacyZoneRouteUploadPreparer: RouteUploadPreparer {
    private let nextRadius: () -> Double

    init(nextRadius: @escaping () -> Double = {
        var generator = SystemRandomNumberGenerator()
        return RouteSharePrivacy.randomCoachUploadRadius(using: &generator)
    }) {
        self.nextRadius = nextRadius
    }

    func prepare(_ points: [RunRoutePoint], distanceMeters: Double) -> RouteUploadPreparation {
        let radius = RouteSharePrivacy.coachUploadRadius(nextRadius())
        // Rounding to five decimals can shift a point by less than one meter.
        let kept = distanceMeters.isFinite && distanceMeters >= RouteSharePrivacy.coachUploadMinimumRunMeters
            ? RouteSharePrivacy.pointsOutsideEndpointRadius(points, radiusMeters: radius + 1)
            : []
        return RouteUploadPreparation(
            points: CoachRouteCoordinate.encodePreparedPoints(kept) ?? [],
            radiusMeters: radius
        )
    }
}

struct PendingCoachRoute: Codable, Equatable {
    let ownerID: UUID
    let linkID: UUID
    let runID: UUID
    /// Prepared coordinates only. Empty when `status` is `tooShort`. Never raw route points.
    let points: [CoachRouteCoordinate]
    /// Chosen once at staging and reused for every retry of this upload.
    let radiusMeters: Double
    let status: CoachRouteVisibility
}

/// Owner update for a run whose route must stay null. No coordinates.
struct CoachRouteTooShortUpdate: Encodable, Equatable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .route)
        try container.encode(CoachRouteVisibility.tooShort.rawValue, forKey: .routeStatus)
    }

    enum CodingKeys: String, CodingKey {
        case route
        case routeStatus = "route_status"
    }
}

struct CoachRunRowID: Decodable {
    let id: Int64
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

struct CoachMapKey: Codable, Hashable {
    let ownerID: UUID
    let runID: UUID
}

struct CoachMapChoice: Codable, Equatable {
    var hidden = false
    var needsSync = false
    var unhideLinkID: UUID?

    func canSync(activeLinkID: UUID?) -> Bool {
        needsSync && (hidden || (activeLinkID != nil && unhideLinkID == activeLinkID))
    }
}

extension PendingCoachRoute {
    var mapKey: CoachMapKey { .init(ownerID: ownerID, runID: runID) }
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

    private static let choicesKey = "runsmart.coachMapChoices.v1"
    @Published private(set) var choices: [CoachMapKey: CoachMapChoice] {
        didSet { defaults.set(try? JSONEncoder().encode(choices), forKey: Self.choicesKey) }
    }

    func choice(for key: CoachMapKey) -> CoachMapChoice? {
        if let choice = choices[key] { return choice }
        // Includes queued routes from versions before per-run controls existed.
        return pending.contains { $0.mapKey == key && $0.status == .shared } ? CoachMapChoice() : nil
    }

    func setHidden(_ hidden: Bool, for key: CoachMapKey, linkID: UUID) {
        guard let choice = choice(for: key), choice.hidden != hidden else { return }
        choices[key] = CoachMapChoice(hidden: hidden, needsSync: true, unhideLinkID: hidden ? nil : linkID)
    }

    func recordServerState(_ hidden: Bool?, for key: CoachMapKey, expected: CoachMapChoice?) {
        guard choices[key] == expected, expected?.needsSync != true else { return }
        // No server row is expected for a map hidden before its first upload.
        if hidden == nil, pending.contains(where: { $0.mapKey == key }) { return }
        choices[key] = hidden.map { CoachMapChoice(hidden: $0) }
    }

    func acknowledge(_ choice: CoachMapChoice, for key: CoachMapKey) {
        guard choices[key] == choice else { return }
        choices[key] = CoachMapChoice(hidden: choice.hidden)
    }

    init(defaults: UserDefaults = .standard, enabled: Bool? = nil,
         preparer: (any RouteUploadPreparer)? = nil) {
        self.defaults = defaults
        choices = defaults.data(forKey: Self.choicesKey).flatMap {
            try? JSONDecoder().decode([CoachMapKey: CoachMapChoice].self, from: $0)
        } ?? [:]
        self.enabled = enabled ?? RouteUploadPolicy.isEnabled
        self.preparer = preparer ?? PrivacyZoneRouteUploadPreparer()
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
        for item in pending where item.ownerID == ownerID && item.linkID == linkID {
            if choices[item.mapKey]?.needsSync != true { choices.removeValue(forKey: item.mapKey) }
        }
        pending = pending.filter { $0.ownerID != ownerID || $0.linkID != linkID }
    }

    private(set) var pending: [PendingCoachRoute] {
        get {
            guard let data = defaults.data(forKey: queueKey) else { return [] }
            return (try? JSONDecoder().decode([PendingCoachRoute].self, from: data)) ?? []
        }
        set {
            objectWillChange.send()
            defaults.set(try? JSONEncoder().encode(newValue), forKey: queueKey)
        }
    }

    /// Call only with the fresh recorder result. Import/consolidation never stages routes.
    /// The queue stores the preparer's output only. Raw `routePoints` are never serialized.
    func stage(_ run: RecordedRun, ownerID: UUID, link: CoachLink, coachModeEnabled: Bool) {
        guard enabled, coachModeEnabled,
              RouteUploadPolicy.isEligible(run: run, link: link, sharing: sharing(ownerID: ownerID, linkID: link.id))
        else { return }

        var queue = pending
        guard !queue.contains(where: { $0.ownerID == ownerID && $0.runID == run.id }) else { return }

        let preparation = preparer.prepare(run.routePoints, distanceMeters: run.distanceMeters)
        let shared = preparation.status == .shared
        let item = PendingCoachRoute(
            ownerID: ownerID, linkID: link.id, runID: run.id,
            points: shared ? preparation.points : [],
            radiusMeters: preparation.radiusMeters,
            status: shared ? .shared : .tooShort
        )
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
            guard choices[item.mapKey]?.hidden != true, pending.contains(item),
                  sharing(ownerID: ownerID, linkID: item.linkID), canSend(item) else { continue }
            do {
                let result = try await send(item)
                if result == .saved, item.status == .shared, pending.contains(item), choices[item.mapKey] == nil {
                    choices[item.mapKey] = CoachMapChoice()
                }
                if result != .missing { pending = pending.filter { $0 != item } }
            } catch {
                // Keep the prepared route for the next sync or foreground.
            }
        }
    }
}
