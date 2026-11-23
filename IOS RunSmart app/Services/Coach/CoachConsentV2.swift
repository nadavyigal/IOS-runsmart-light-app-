import Combine
import Foundation
import Supabase

// Coach Experience v2, story C7.8: consent v2 and the one-time P9 notice for athletes
// who joined before v2. "Coach" means a HUMAN coach (Coach Mode), not the AI coach.
//
// Server side: supabase/migrations/20261121110000_coach_consent_v2.sql. The server is the
// real gate (D7): nothing is shared until ack_coach_consent(2), whatever this file shows.

enum CoachConsentV2RPC {
    static let status = "my_coach_consent_status"
    static let acknowledge = "ack_coach_consent"
    static let inviteConsentVersion = "coach_invite_consent_version"
    static let joinV2 = "join_coach_v2"
}

/// Where the v2 consent copy was shown. Raw values are analytics enums (v1.3 section 3.8).
nonisolated enum CoachConsentSurface: String, Sendable {
    /// P8, the join consent screen.
    case join
    /// P9, the one-time notice on Today.
    case notice
}

/// `my_coach_consent_status()`: the caller's own active link, never anyone else's.
nonisolated struct CoachConsentStatus: Equatable, Sendable {
    let linkID: UUID
    let coachName: String
    /// The pair is v2 right now (kill switch on, both clients v2, allowlist rule).
    let linkIsV2: Bool
    /// Show P9: the pair is v2 and the athlete has not accepted the v2 copy.
    let needsV2Ack: Bool
    /// The athlete accepted and the pair is v2.
    let sharingActive: Bool
}

nonisolated protocol CoachConsentRepository: Sendable {
    func status() async throws -> CoachConsentStatus?
    /// `ack_coach_consent(2)`. Idempotent on the server.
    func acknowledge() async throws
}

nonisolated struct SupabaseCoachConsentRepository: CoachConsentRepository {
    private struct StatusRow: Decodable {
        let linkID: UUID
        let coachDisplayName: String
        let linkIsV2: Bool
        let needsV2Ack: Bool
        let sharingActive: Bool

        enum CodingKeys: String, CodingKey {
            case linkID = "link_id"
            case coachDisplayName = "coach_display_name"
            case linkIsV2 = "link_is_v2"
            case needsV2Ack = "needs_v2_ack"
            case sharingActive = "sharing_active"
        }
    }

    private struct AckParams: Encodable {
        let version: Int

        enum CodingKeys: String, CodingKey {
            case version = "p_version"
        }
    }

    func status() async throws -> CoachConsentStatus? {
        let rows: [StatusRow] = try await SupabaseManager.client
            .rpc(CoachConsentV2RPC.status)
            .execute()
            .value
        return rows.first.map {
            CoachConsentStatus(
                linkID: $0.linkID,
                coachName: $0.coachDisplayName,
                linkIsV2: $0.linkIsV2,
                needsV2Ack: $0.needsV2Ack,
                sharingActive: $0.sharingActive
            )
        }
    }

    func acknowledge() async throws {
        try await SupabaseManager.client
            .rpc(CoachConsentV2RPC.acknowledge, params: AckParams(version: 2))
            .execute()
    }
}

/// What P9 renders. One per link.
nonisolated struct CoachConsentNotice: Equatable, Sendable, Identifiable {
    let linkID: UUID
    let coachName: String

    var id: UUID { linkID }
}

/// P9 on Today. Asks the server once per Today open while v2 is on and the athlete is
/// linked. With v2 off it makes no call and shows nothing (flag-off AC).
///
/// A swipe-away or a failed OK hides P9 until the next foreground, then it shows again
/// (C7.8 AC4). The server decides who needs it, so an athlete who accepted on TestFlight
/// never sees it again on a later build (AC5).
@MainActor
final class CoachConsentNoticeModel: ObservableObject {
    @Published private(set) var notice: CoachConsentNotice?
    @Published private(set) var isWorking = false

    private let repository: any CoachConsentRepository
    private let analytics: () -> any AnalyticsTracking
    /// Links whose P9 waits for the next foreground.
    private var deferredLinks: Set<UUID> = []
    private var generation = 0

    init(
        repository: any CoachConsentRepository = SupabaseCoachConsentRepository(),
        analytics: @escaping () -> any AnalyticsTracking = { Analytics.shared }
    ) {
        self.repository = repository
        self.analytics = analytics
    }

    nonisolated deinit {}

    /// Call when Today opens and when the inputs change. Offline, the read fails and P9
    /// waits for a connection.
    func evaluate(v2Enabled: Bool, userID: UUID?, linkID: UUID?) async {
        generation += 1
        let current = generation
        guard v2Enabled, userID != nil, let linkID else {
            notice = nil
            return
        }
        guard !deferredLinks.contains(linkID) else { return }
        if notice?.linkID == linkID { return }
        let status: CoachConsentStatus?
        do {
            status = try await repository.status()
        } catch {
            if !(error is CancellationError) {
                print("[CoachConsentNotice] status read failed:", error)
            }
            return
        }
        guard current == generation, !deferredLinks.contains(linkID) else { return }
        guard let status, status.linkID == linkID, status.needsV2Ack else {
            notice = nil
            return
        }
        notice = CoachConsentNotice(linkID: status.linkID, coachName: status.coachName)
        CoachV2Analytics.track(.consentV2Shown(surface: .notice), to: analytics())
    }

    /// A new foreground counts as a new open: deferred notices may show again.
    func beginForeground() {
        deferredLinks.removeAll()
    }

    /// P9 OK. Returns true when the server recorded the ack.
    @discardableResult
    func acknowledge() async -> Bool {
        guard let shown = notice, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.acknowledge()
            CoachV2Analytics.track(.consentV2Acked(surface: .notice), to: analytics())
            if notice == shown { notice = nil }
            // C7.3: sharing starts now, and the one-time RPE backfill runs right after the ack.
            NotificationCenter.default.post(name: .coachConsentV2Acked, object: nil)
            // C7.10 AC3: P10 follows P9's OK.
            NotificationCenter.default.post(name: .remotePushAthleteContext, object: shown.coachName)
            return true
        } catch {
            // Nothing was shared. P9 comes back on the next open.
            if !(error is CancellationError) {
                print("[CoachConsentNotice] ack failed:", error)
            }
            deferredLinks.insert(shown.linkID)
            if notice == shown { notice = nil }
            return false
        }
    }

    /// P9 "Leave {Coach}". The leave sheet opens; P9 stays pending until the athlete
    /// leaves or taps OK.
    func leaveTapped() {
        guard notice != nil else { return }
        CoachV2Analytics.track(.consentV2LeaveTapped(surface: .notice), to: analytics())
    }

    /// Swiped away: shows again on the next foreground.
    func dismissForNow() {
        guard let shown = notice else { return }
        deferredLinks.insert(shown.linkID)
        notice = nil
    }
}
