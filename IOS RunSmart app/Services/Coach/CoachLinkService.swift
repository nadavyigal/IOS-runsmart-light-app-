import Foundation
import Combine
import Supabase

// "Coach" in this file means a HUMAN coach (Coach Mode). It is unrelated to the AI
// coach: `coach_message`, `profiles.coaching_style`, `CoachFlowView`.

struct CoachLink: Equatable, Sendable {
    let id: UUID
    let coachID: UUID
    let coachName: String
    let consentedAt: Date
}

struct CoachLookup: Equatable, Sendable {
    /// The invite row that was shown. Share refuses to join a different row.
    let inviteID: UUID
    let coachID: UUID
    let displayName: String
    /// The exact code that produced this lookup. Share does not read the text field.
    let code: String
    /// Nil on a database that has not applied Story 1.8 yet. That keeps Story 1.3's immediate join.
    var planMode: CoachPlanMode? = nil
    /// Present only for a Group Plan coach whose settings came back complete.
    var groupPlan: GroupPlanSettings? = nil
    /// C7.8: which consent copy the athlete sees. 1 = the MVP A3 copy, 2 = the v2 P8
    /// copy. Stays 1 unless v2 is on and `coach_invite_consent_version` says 2.
    var consentVersion: Int = 1
}

enum JoinCoachOutcome: Equatable, Sendable {
    case joined(CoachLink)
    case alreadyLinked(coachName: String)
}

enum CoachLinkServiceError: Error, Equatable {
    case invalidCode
    case alreadyLinked(coachName: String)
    case consentMismatch
    case offline
    case notSignedIn
    case notLinked
}

/// Reads and creates the athlete's consent link. Later Coach Mode stories reuse this.
nonisolated protocol CoachLinkRepository: Sendable {
    func currentLink() async throws -> CoachLink?
    func lookupInvite(code: String) async throws -> CoachLookup?
    func joinCoach(code: String, inviteID: UUID, coachID: UUID, athleteID: UUID) async throws -> JoinCoachOutcome
    func leaveCoach(linkID: UUID) async throws
    /// C7.8: `coach_invite_consent_version(code)`. 2 when the P8 copy applies, else 1.
    func inviteConsentVersion(code: String) async throws -> Int
    /// C7.8: `join_coach_v2`. Version 2 writes the ack in the same call (AC2).
    func joinCoach(code: String, inviteID: UUID, coachID: UUID, athleteID: UUID,
                   consentVersion: Int) async throws -> JoinCoachOutcome
}

extension CoachLinkRepository {
    /// Repositories without the v2 RPCs show the A3 copy.
    func inviteConsentVersion(code: String) async throws -> Int { 1 }

    func joinCoach(code: String, inviteID: UUID, coachID: UUID, athleteID: UUID,
                   consentVersion: Int) async throws -> JoinCoachOutcome {
        try await joinCoach(code: code, inviteID: inviteID, coachID: coachID, athleteID: athleteID)
    }
}

nonisolated struct SupabaseCoachLinkRepository: CoachLinkRepository {
    private struct LinkRow: Decodable {
        let linkId: UUID
        let coachId: UUID
        let displayName: String
        let consentedAt: Date

        enum CodingKeys: String, CodingKey {
            case linkId = "link_id"
            case coachId = "coach_id"
            case displayName = "display_name"
            case consentedAt = "consented_at"
        }

        var link: CoachLink {
            CoachLink(id: linkId, coachID: coachId, coachName: displayName, consentedAt: consentedAt)
        }
    }

    private enum JoinPayload: Decodable {
        case joined(LinkRow)
        case alreadyLinked(String)

        private enum CodingKeys: String, CodingKey {
            case status
            case displayName = "display_name"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .status) {
            case "joined":
                self = .joined(try LinkRow(from: decoder))
            case "already_linked":
                self = .alreadyLinked(try container.decode(String.self, forKey: .displayName))
            default:
                throw CoachLinkServiceError.invalidCode
            }
        }
    }

    private struct CodeParams: Encodable {
        let code: String
    }

    private struct JoinParams: Encodable {
        let code: String
        let expectedInviteId: UUID
        let expectedCoachId: UUID
        let expectedAthleteId: UUID

        enum CodingKeys: String, CodingKey {
            case code
            case expectedInviteId = "expected_invite_id"
            case expectedCoachId = "expected_coach_id"
            case expectedAthleteId = "expected_athlete_id"
        }
    }

    private struct JoinV2Params: Encodable {
        let code: String
        let expectedInviteId: UUID
        let expectedCoachId: UUID
        let expectedAthleteId: UUID
        let consentVersion: Int

        enum CodingKeys: String, CodingKey {
            case code
            case expectedInviteId = "expected_invite_id"
            case expectedCoachId = "expected_coach_id"
            case expectedAthleteId = "expected_athlete_id"
            case consentVersion = "p_consent_version"
        }
    }

    func currentLink() async throws -> CoachLink? {
        let rows: [LinkRow] = try await SupabaseManager.client
            .rpc("my_coach_link")
            .execute()
            .value
        return rows.first?.link
    }

    func lookupInvite(code: String) async throws -> CoachLookup? {
        let rows: [CoachInviteLookupRow] = try await SupabaseManager.client
            .rpc("lookup_invite", params: CodeParams(code: code))
            .execute()
            .value
        return rows.first?.coachLookup(code: code)
    }

    func joinCoach(code: String, inviteID: UUID, coachID: UUID, athleteID: UUID) async throws -> JoinCoachOutcome {
        let payload: JoinPayload = try await SupabaseManager.client
            .rpc(
                "join_coach",
                params: JoinParams(code: code, expectedInviteId: inviteID, expectedCoachId: coachID,
                                   expectedAthleteId: athleteID)
            )
            .execute()
            .value
        return Self.outcome(payload)
    }

    func inviteConsentVersion(code: String) async throws -> Int {
        try await SupabaseManager.client
            .rpc(CoachConsentV2RPC.inviteConsentVersion, params: CodeParams(code: code))
            .execute()
            .value
    }

    /// Version 1 goes through Story 1.3's `join_coach`, exactly as before.
    func joinCoach(code: String, inviteID: UUID, coachID: UUID, athleteID: UUID,
                   consentVersion: Int) async throws -> JoinCoachOutcome {
        guard consentVersion >= 2 else {
            return try await joinCoach(code: code, inviteID: inviteID, coachID: coachID, athleteID: athleteID)
        }
        let payload: JoinPayload = try await SupabaseManager.client
            .rpc(
                CoachConsentV2RPC.joinV2,
                params: JoinV2Params(code: code, expectedInviteId: inviteID, expectedCoachId: coachID,
                                     expectedAthleteId: athleteID, consentVersion: 2)
            )
            .execute()
            .value
        return Self.outcome(payload)
    }

    private static func outcome(_ payload: JoinPayload) -> JoinCoachOutcome {
        switch payload {
        case .joined(let row):
            return .joined(row.link)
        case .alreadyLinked(let coachName):
            return .alreadyLinked(coachName: coachName)
        }
    }

    func leaveCoach(linkID: UUID) async throws {
        try await SupabaseManager.client
            .rpc("leave_coach", params: ["expected_link_id": linkID])
            .execute()
    }
}


/// `{INVITE_BASE_URL}/join/{CODE}`. The host is `ExternalURLs.inviteBase`; there is no second host.
enum InviteLink {
    /// Story 1.2 alphabet (`v_alphabet` in `20261114210000_coach_role_and_invites.sql`).
    static let alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    static let length = 6

    enum Route: Equatable {
        case ignored
        case unresolved
        case code(String)
    }

    /// A matching invite URL with a 6-character alphabet code, a `/join` URL whose code is
    /// not that shape, or anything else (wrong host, wrong path, junk).
    static func route(for url: URL, base: URL = ExternalURLs.inviteBase) -> Route {
        guard let baseHost = base.host, let host = url.host,
              host.caseInsensitiveCompare(baseHost) == .orderedSame,
              url.scheme?.caseInsensitiveCompare(base.scheme ?? "https") == .orderedSame
        else { return .ignored }

        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.first?.caseInsensitiveCompare("join") == .orderedSame else { return .ignored }
        guard parts.count == 2, let code = normalizedCode(parts[1]) else { return .unresolved }
        return .code(code)
    }

    /// Bare code, or a full invite link. Does not read the clipboard.
    static func code(inPasted text: String, base: URL = ExternalURLs.inviteBase) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let code = normalizedCode(trimmed) { return code }
        guard let url = URL(string: trimmed), case .code(let code) = route(for: url, base: base) else {
            return nil
        }
        return code
    }

    static func normalizedCode(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == length else { return nil }
        let allowed = CharacterSet(charactersIn: alphabet)
        guard code.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return code
    }
}

/// Current link plus the coach's name. Settings uses `showsJoinCoach`.
@MainActor
final class CoachLinkStore: ObservableObject {
    @Published private(set) var currentLink: CoachLink? {
        didSet { publishAssistantContext() }
    }
    @Published private(set) var didAttemptLoad = false

    /// Kept when Continue sends a signed-out athlete to sign in, so A1 still has the code after.
    /// A valid invite link uses the same two fields (Story 1.4).
    @Published var draftCode = ""
    @Published var resumeJoinAfterSignIn = false

    /// Set when an invite link arrives. The join screen consumes it once.
    @Published var pendingInvite: PendingInvite?

    enum PendingInvite: Equatable {
        /// Open A1 with this code filled in, then run lookup.
        case code(String)
        /// Open A1 with an empty field and the unresolved hint.
        case unresolved
    }

    private let repository: any CoachLinkRepository
    /// Only the app's store publishes into AI requests. Tests keep the default so they cannot leak a link.
    private let publishesAssistantContext: Bool
    /// Bumped when the signed-in athlete changes, so an older refresh cannot publish.
    private var loadGeneration = 0
    /// The only user id whose refresh may publish. Nil after sign-out.
    private var acceptedUserID: UUID?

    init(
        repository: any CoachLinkRepository = SupabaseCoachLinkRepository(),
        publishesAssistantContext: Bool = false
    ) {
        self.repository = repository
        self.publishesAssistantContext = publishesAssistantContext
    }

    private func publishAssistantContext() {
        guard publishesAssistantContext else { return }
        CoachContextSource.shared.replace(CoachContext.forRequest(link: currentLink), ownerID: acceptedUserID)
    }

    /// The Settings row is shown only when we know there is no active link.
    var showsJoinCoach: Bool {
        didAttemptLoad && currentLink == nil
    }

    /// Set after a successful leave. Settings shows it, then clears it.
    @Published var leaveNotice: String?

    func activeLink(for userID: UUID?) -> CoachLink? {
        guard let userID, acceptedUserID == userID else { return nil }
        return currentLink
    }

    /// Call when the signed-in athlete changes, before any refresh for that athlete.
    func beginSession(userID: UUID) {
        guard acceptedUserID != userID else { return }
        discardCurrentRouteQueue()
        loadGeneration += 1
        acceptedUserID = userID
        currentLink = nil
        leaveNotice = nil
        didAttemptLoad = false
    }

    private func discardCurrentRouteQueue() {
        if let acceptedUserID, let currentLink {
            CoachRouteOutbox.shared.discard(ownerID: acceptedUserID, linkID: currentLink.id)
        }
    }

    func clear() {
        discardCurrentRouteQueue()
        loadGeneration += 1
        acceptedUserID = nil
        currentLink = nil
        leaveNotice = nil
        didAttemptLoad = false
    }

    /// Publishes only if `userID` is still the accepted session after the read returns.
    func refresh(userID: UUID) async {
        guard acceptedUserID == userID else { return }
        let generation = loadGeneration
        let capturedUserID = userID
        do {
            let link = try await repository.currentLink()
            guard generation == loadGeneration, acceptedUserID == capturedUserID else { return }
            if currentLink?.id != link?.id { discardCurrentRouteQueue() }
            currentLink = link
            didAttemptLoad = true
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, acceptedUserID == capturedUserID else { return }
            // A failed read must not pretend the athlete is linked, or the row would vanish.
            didAttemptLoad = true
            print("[CoachLinkStore] current link failed:", error)
        }
    }

    func consumeJoinIntent(isAuthenticated: Bool, onboardingComplete: Bool) -> Bool {
        guard isAuthenticated, onboardingComplete, resumeJoinAfterSignIn else { return false }
        resumeJoinAfterSignIn = false
        return true
    }

    /// Clears the cached link only after leave_coach succeeds.
    func leave(userID: UUID, expectedLinkID: UUID? = nil) async throws {
        guard acceptedUserID == userID, let link = currentLink,
              expectedLinkID == nil || expectedLinkID == link.id else {
            throw CoachLinkServiceError.notSignedIn
        }
        let generation = loadGeneration
        do {
            try await repository.leaveCoach(linkID: link.id)
        } catch let leaveError {
            // A response may be lost after the server committed the revoke.
            guard acceptedUserID == userID, generation == loadGeneration else { throw CancellationError() }
            let authoritativeLink: CoachLink?
            do {
                authoritativeLink = try await repository.currentLink()
            } catch {
                throw leaveError
            }
            guard authoritativeLink == nil else { throw leaveError }
        }
        guard acceptedUserID == userID, generation == loadGeneration else { throw CancellationError() }
        if let currentLink, currentLink.id != link.id { throw CancellationError() }
        CoachRouteOutbox.shared.discard(ownerID: userID, linkID: link.id)
        loadGeneration += 1
        currentLink = nil
        didAttemptLoad = true
    }

    /// Records an invite link. Returns true when this URL must not be handled as sign-in.
    /// Coach Mode off stores nothing and does not open the join screen.
    @discardableResult
    func receiveInviteLink(_ url: URL, coachModeEnabled: Bool, canOpenJoinNow: Bool) -> Bool {
        let route = InviteLink.route(for: url)
        let isInviteAttempt = route != .ignored || RunSmartFeatures.isCoachInviteURL(url)
        guard coachModeEnabled, route != .ignored else { return isInviteAttempt }
        switch route {
        case .ignored:
            return isInviteAttempt
        case .unresolved:
            draftCode = ""
            pendingInvite = .unresolved
        case .code(let code):
            draftCode = code
            pendingInvite = .code(code)
        }
        // Guests and unfinished onboarding keep the code until A1 can open. Story 1.3's flag.
        resumeJoinAfterSignIn = !canOpenJoinNow
        return true
    }

    func noteJoined(_ link: CoachLink, userID: UUID) {
        guard acceptedUserID == userID else { return }
        loadGeneration += 1
        currentLink = link
        didAttemptLoad = true
        draftCode = ""
        resumeJoinAfterSignIn = false
        pendingInvite = nil
    }
}

/// A1 and A3 copy. The consent sentences are the story's source of truth.
enum CoachConsentCopy {
    static let invalidCode = "That code doesn't work. Check it with your coach."
    static let offline = "You need to be online to join."
    /// A2 when the link cannot be resolved. The manual field stays empty.
    static let unresolvedLinkHint = "Enter your coach's code"

    /// Shown when the code no longer names the coach on the consent screen. Share does not link.
    static func codeReassigned(coach: String) -> String {
        "This code now belongs to \(coach)"
    }

    static func alreadyLinked(coach: String) -> String {
        "You're with \(coach). Leave \(coach) first to join another coach."
    }

    static func title(coach: String) -> String {
        "Share with \(coach)?"
    }

    /// Body under the title, word for word from Story 1.3.
    static func body(coach: String) -> String {
        """
        \(coach) can see:
        • Your training plan
        • Your runs: distance, time, pace and average heart rate
        • Route maps of new runs you record in RunSmart. The start and end of each route are trimmed for privacy.

        \(coach) can also change your upcoming workouts.

        Not shared: your chats with RunSmart, and health data such as sleep or HRV.

        If you leave, \(coach) will no longer see your runs. You keep any feedback \(coach) has already given you. You can leave anytime in Settings.
        """
    }

    /// C7.8 P8: the v2 join consent body, word for word from the UX spec (section C.5),
    /// plus the D9 read-receipt line (v1.3 C7.8 AC1). The lock sentence ("RunSmart won't
    /// change workouts {Coach} sets.") is added only when `LeaveCoachCopy.coachWorkoutLocksEnabled`
    /// is true, the same rule the A13 leave sheet uses: before C8.1a it would not be true.
    static func v2Body(coach: String) -> String {
        let workouts = LeaveCoachCopy.coachWorkoutLocksEnabled
            ? "\(coach) can also set and change your upcoming workouts. RunSmart won't change workouts \(coach) sets."
            : "\(coach) can also set and change your upcoming workouts."
        return """
        \(coach) can see:
        • Your training plan
        • Your runs: distance, time, pace and average heart rate
        • Route maps of runs you record in RunSmart, with the start and end trimmed for privacy
        • How hard each run felt (effort 1–10)
        • Notes you add to your runs. You can hide any note from \(coach).
        • Pain or "something off" flags you send

        \(readReceipts(coach: coach))

        \(workouts)

        Not shared: your chats with RunSmart, and health data such as sleep or HRV.

        If you leave, \(coach) will no longer see your runs. You keep any feedback \(coach) has already given you. You can leave anytime in Settings.
        """
    }

    /// Decision D9: the coach can see when the athlete reads group messages.
    static func readReceipts(coach: String) -> String {
        "\(coach) can see when you read group messages."
    }

    /// C7.8 P9 title, for athletes who joined before v2.
    static func noticeTitle(coach: String) -> String {
        "\(coach) can now see how your runs felt"
    }

    /// C7.8 P9 body, word for word from the UX spec (section C.5). The effort line is the
    /// spec's variant for the D7 14-day effort backfill; the read-receipt line is D9.
    static func noticeBody(coach: String) -> String {
        """
        From now on, \(coach) can see:
        • How hard each run felt (effort 1–10)
        • Notes you add to runs. You can hide any note from \(coach).
        • Pain or "something off" flags you send

        \(readReceipts(coach: coach))

        Notes you wrote before today stay on this phone.
        Effort from your last 14 days is shared too.
        """
    }

    static let noticeOK = "OK"

    static func noticeLeave(coach: String) -> String {
        "Leave \(coach)"
    }

    /// The three "can see" bullets on the consent screen. My coach repeats them.
    static func sharedBullets() -> [String] {
        [
            "Your training plan",
            "Your runs: distance, time, pace and average heart rate",
            "Route maps of new runs you record in RunSmart. The start and end of each route are trimmed for privacy.",
        ]
    }
}

/// A13 copy. `{Coach}` is the coach's display name. Do not reword these sentences.
enum LeaveCoachCopy {
    /// Story 4.1 (workout locks) flips this. While false, A13 omits the lock sentence.
    static let coachWorkoutLocksEnabled = false

    static let failure = "Couldn't leave right now. You're still linked. Try again."
    static let offline = "Connect to the internet"

    static func monogram(for name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        let letters = parts.prefix(2).compactMap(\.first)
        let text = String(letters).uppercased()
        return text.isEmpty ? "?" : text
    }

    static func title(coach: String) -> String {
        "Leave \(coach)?"
    }

    static func toast(coach: String) -> String {
        "You left \(coach). \(coach) no longer sees your runs."
    }

    /// Full sheet body, including the title line. The lock bullet is included only when
    /// `coachWorkoutLocksEnabled` is true. `includesV2Lines` (C7.8 AC8, UX gap G17) adds the
    /// effort, notes and flags line and the replies line; pass true only while v2 is on and
    /// the link is v2, so the flag-off sheet stays the 1.2.6 sheet.
    static func sheet(coach: String, includesV2Lines: Bool = false) -> String {
        var stops = [
            "• \(coach) won't see your plan, runs or maps.",
        ]
        if includesV2Lines {
            stops.append("• \(coach) won't see your effort, notes or flags.")
        }
        stops.append(contentsOf: [
            "• \(coach) won't review your runs or send new feedback.",
            "• \(coach) can't change your workouts.",
        ])
        if coachWorkoutLocksEnabled {
            stops.append("• Workouts \(coach) set are no longer protected, so RunSmart may adjust them.")
        }
        stops.append("• \(coach)'s name and notes are removed from your plan.")
        let stopBlock = stops.joined(separator: "\n")
        var stays = [
            "• Your plan, which RunSmart keeps adapting.",
            "• Your run history.",
            "• Feedback \(coach) has already given you. You can still read it on the runs it was written for.",
        ]
        if includesV2Lines {
            stays.append("• Your replies to \(coach)'s notes.")
        }
        let stayBlock = stays.joined(separator: "\n")
        return """
        \(title(coach: coach))
        If you leave, \(coach) will no longer see your runs.

        What stops:
        \(stopBlock)

        What stays:
        \(stayBlock)

        You can join a coach again with a code.
        """
    }
}

/// Leave confirm. Cancel does not call the server. A failed RPC leaves the link in place.
@MainActor
final class LeaveCoachModel: ObservableObject {
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published var isOnline: Bool

    /// C7.11: `athlete_left_coach` is a v2 event, so it is sent only while v2 is on.
    private let coachV2Enabled: () -> Bool
    private let analytics: () -> any AnalyticsTracking

    init(
        isOnline: Bool = true,
        coachV2Enabled: @escaping () -> Bool = { RunSmartFeatures.coachV2Enabled },
        analytics: @escaping () -> any AnalyticsTracking = { Analytics.shared }
    ) {
        self.isOnline = isOnline
        self.coachV2Enabled = coachV2Enabled
        self.analytics = analytics
    }

    var leaveDisabledReason: String? {
        isOnline ? nil : LeaveCoachCopy.offline
    }

    func cancel() {
        errorMessage = nil
    }

    /// Returns the toast after the link is cleared. Nil keeps the athlete linked.
    func confirm(coachName: String, userID: UUID, store: CoachLinkStore, expectedLinkID: UUID? = nil) async -> String? {
        guard !isWorking else { return nil }
        errorMessage = nil
        guard isOnline else {
            errorMessage = LeaveCoachCopy.offline
            return nil
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await store.leave(userID: userID, expectedLinkID: expectedLinkID)
            guard store.currentLink == nil else { return nil }
            let toast = LeaveCoachCopy.toast(coach: coachName)
            store.leaveNotice = toast
            if coachV2Enabled() {
                CoachV2Analytics.track(.athleteLeftCoach, to: analytics())
            }
            return toast
        } catch {
            errorMessage = LeaveCoachCopy.failure
            return nil
        }
    }
}

enum JoinCoachPhase: Equatable {
    case enterCode
    /// Skeleton of the consent screen while a link's lookup is in flight.
    case resolvingLink
    case consent(CoachLookup, athleteID: UUID)
    /// A4. The link does not exist yet.
    case groupConfirm(GroupPlanConfirm)
    /// "Building your plan…" The link is created only after this succeeds.
    case building(coachName: String)
}

@MainActor
final class JoinCoachViewModel: ObservableObject {
    @Published var code: String
    @Published private(set) var phase: JoinCoachPhase = .enterCode
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published private(set) var joinedCoach: CoachLink?
    /// Where to land after a successful link. Individual Plans with no plan opens Build my plan.
    @Published private(set) var followUp: JoinCoachFollowUp = .today
    /// A2 hint. The typed-code field does not show this on its own.
    @Published private(set) var showsEntryHint = false

    private let repository: any CoachLinkRepository
    var plans: (any GroupPlanAthleteContext)?
    private let now: @Sendable () -> Date
    let calendar: Calendar
    /// C7.8: v2 on for this user. Off keeps the A3 copy and Story 1.3's join, with no v2 call.
    private let coachV2Enabled: () -> Bool
    private let analytics: () -> any AnalyticsTracking

    init(
        code: String = "",
        repository: any CoachLinkRepository = SupabaseCoachLinkRepository(),
        plans: (any GroupPlanAthleteContext)? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current,
        coachV2Enabled: @escaping () -> Bool = { RunSmartFeatures.coachV2Enabled },
        analytics: @escaping () -> any AnalyticsTracking = { Analytics.shared }
    ) {
        self.code = code
        self.repository = repository
        self.plans = plans
        self.now = now
        self.calendar = calendar
        self.coachV2Enabled = coachV2Enabled
        self.analytics = analytics
    }

    /// C7.8 AC1 + AC7: with v2 on, asks the server whether the P8 copy applies to this
    /// coach. Any failure keeps the A3 copy; the athlete then sees P9 once the link is v2.
    private func withConsentVersion(_ coach: CoachLookup) async -> CoachLookup {
        guard coachV2Enabled() else { return coach }
        var resolved = coach
        let version = (try? await repository.inviteConsentVersion(code: coach.code)) ?? 1
        resolved.consentVersion = version >= 2 ? 2 : 1
        return resolved
    }

    /// Shows the consent screen. Counts P8 as shown when the v2 copy is on screen.
    private func showConsent(_ coach: CoachLookup, athleteID: UUID) {
        phase = .consent(coach, athleteID: athleteID)
        if coach.consentVersion >= 2 {
            CoachV2Analytics.track(.consentV2Shown(surface: .join), to: analytics())
        }
    }

    /// Story 1.3's join for the A3 copy; `join_coach_v2` with the ack for the P8 copy.
    private func join(_ coach: CoachLookup, athleteID: UUID) async throws -> JoinCoachOutcome {
        guard coach.consentVersion >= 2 else {
            return try await repository.joinCoach(
                code: coach.code, inviteID: coach.inviteID, coachID: coach.coachID, athleteID: athleteID
            )
        }
        let outcome = try await repository.joinCoach(
            code: coach.code, inviteID: coach.inviteID, coachID: coach.coachID, athleteID: athleteID,
            consentVersion: 2
        )
        if case .joined = outcome {
            CoachV2Analytics.track(.consentV2Acked(surface: .join), to: analytics())
        }
        return outcome
    }

    /// The live join screen calls this once. Tests pass their own context and this does not replace it.
    func attachLivePlansIfNeeded(
        services: any RunSmartServiceProviding,
        profile: @escaping () -> OnboardingProfile
    ) {
        guard plans == nil else { return }
        plans = LiveGroupPlanContext(services: services, profile: profile)
    }

    var groupFailureMessage: String? {
        guard case .groupConfirm(let confirm) = phase else { return nil }
        switch confirm.failure {
        case .generation:
            return GroupPlanConfirmCopy.generationFailed
        case .join:
            return GroupPlanConfirmCopy.joinFailed(coach: confirm.coach.displayName)
        case nil:
            return nil
        }
    }

    func continueTapped(athleteID: UUID?) async {
        guard !isWorking else { return }
        errorMessage = nil
        showsEntryHint = false
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        code = trimmed
        guard !trimmed.isEmpty else {
            errorMessage = CoachConsentCopy.invalidCode
            return
        }
        // Code entry is only for a signed-in athlete. Callers route guests to sign-in first.
        guard let athleteID else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            if let existing = try await repository.currentLink() {
                phase = .enterCode
                errorMessage = CoachConsentCopy.alreadyLinked(coach: existing.coachName)
                return
            }
            guard let coach = try await repository.lookupInvite(code: trimmed) else {
                phase = .enterCode
                errorMessage = CoachConsentCopy.invalidCode
                return
            }
            showConsent(await withConsentVersion(coach), athleteID: athleteID)
        } catch {
            phase = .enterCode
            errorMessage = Self.message(for: error)
        }
    }

    /// Fills A1 from a system paste. Accepts a bare code or a full invite link.
    func applyPastedText(_ text: String) {
        guard let extracted = InviteLink.code(inPasted: text) else { return }
        code = extracted
        showsEntryHint = false
        errorMessage = nil
    }

    /// Arms the consent skeleton. `resolveFromLink` does the lookup.
    func consumePendingInvite(_ pending: CoachLinkStore.PendingInvite) {
        switch pending {
        case .unresolved:
            code = ""
            errorMessage = nil
            showsEntryHint = true
            isWorking = false
            phase = .enterCode
        case .code(let value):
            code = value
            errorMessage = nil
            showsEntryHint = false
            isWorking = true
            phase = .resolvingLink
        }
    }

    /// Same lookup as a typed code. A miss, an inactive code, or offline leaves A1 empty with the hint.
    /// An athlete who is already linked keeps the code and the Story 1.3 message.
    func resolveFromLink(athleteID: UUID?) async {
        guard case .resolvingLink = phase else { return }
        defer { isWorking = false }
        guard let athleteID else {
            phase = .enterCode
            return
        }
        do {
            if let existing = try await repository.currentLink() {
                phase = .enterCode
                errorMessage = CoachConsentCopy.alreadyLinked(coach: existing.coachName)
                return
            }
            guard let coach = try await repository.lookupInvite(code: code) else {
                landUnresolved()
                return
            }
            showConsent(await withConsentVersion(coach), athleteID: athleteID)
        } catch {
            landUnresolved()
        }
    }

    private func landUnresolved() {
        code = ""
        errorMessage = nil
        showsEntryHint = true
        phase = .enterCode
    }

    /// Not now: leave the consent screen. Does not call join.
    func notNow() {
        joinedCoach = nil
        errorMessage = nil
        phase = .enterCode
    }

    func share(athleteID: UUID) async {
        guard !isWorking, case .consent(let shown, let consentingAthleteID) = phase else { return }
        guard athleteID == consentingAthleteID else {
            notNow()
            return
        }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            guard let resolved = try await repository.lookupInvite(code: shown.code) else {
                phase = .enterCode
                errorMessage = CoachConsentCopy.invalidCode
                return
            }
            // The code now names a different invite or coach. Drop the previous consent.
            if resolved.inviteID != shown.inviteID || resolved.coachID != shown.coachID {
                showConsent(await withConsentVersion(resolved), athleteID: athleteID)
                errorMessage = CoachConsentCopy.codeReassigned(coach: resolved.displayName)
                return
            }
            // The join records the copy the athlete accepted, not a fresh answer.
            var accepted = resolved
            accepted.consentVersion = shown.consentVersion
            if resolved.planMode == .group {
                guard let settings = resolved.groupPlan else {
                    errorMessage = GroupPlanConfirmCopy.generationFailed
                    return
                }
                phase = .groupConfirm(GroupPlanConfirm(
                    coach: accepted,
                    athleteID: athleteID,
                    settings: settings,
                    replacement: await replacementSentence(),
                    failure: nil,
                    planBuilt: false
                ))
                return
            }
            switch try await join(shown, athleteID: consentingAthleteID) {
            case .joined(let coach):
                joinedCoach = coach
                followUp = await individualFollowUp()
            case .alreadyLinked(let coachName):
                phase = .enterCode
                errorMessage = CoachConsentCopy.alreadyLinked(coach: coachName)
            }
        } catch {
            if Self.isConsentMismatch(error) {
                await reshowConsent(for: shown.code, athleteID: athleteID)
                return
            }
            let message = Self.message(for: error)
            if message == CoachConsentCopy.invalidCode || message == CoachConsentCopy.offline
                || message.hasPrefix("You're with ") {
                phase = .enterCode
            }
            errorMessage = message
        }
    }

    /// A4 confirm. Generates under the athlete's login, then calls join_coach.
    /// A failed generation never links. A failed join retries the link only.
    func useGroupPlan(athleteID: UUID) async {
        guard !isWorking, case .groupConfirm(var confirm) = phase, confirm.athleteID == athleteID else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        confirm.failure = nil
        if let notice = GroupPlanRules.dateNotice(
            raceDate: confirm.settings.raceDate,
            targetDistance: confirm.settings.targetDistance,
            today: now(),
            calendar: calendar
        ), notice.blocksSave {
            confirm.failure = .generation
            phase = .groupConfirm(confirm)
            errorMessage = notice.message
            return
        }

        if !confirm.planBuilt {
            guard let plans else {
                confirm.failure = .generation
                phase = .groupConfirm(confirm)
                return
            }
            phase = .building(coachName: confirm.coach.displayName)
            var request = GroupPlanRequest.make(
                settings: confirm.settings,
                profile: plans.profile(),
                today: now(),
                calendar: calendar
            )
            request.groupPlanAthleteID = confirm.athleteID
            let built = await plans.generateAndPersist(request)
            guard built else {
                confirm.failure = .generation
                phase = .groupConfirm(confirm)
                return
            }
            confirm.planBuilt = true
        }

        do {
            switch try await join(confirm.coach, athleteID: confirm.athleteID) {
            case .joined(let coach):
                joinedCoach = coach
                followUp = .today
            case .alreadyLinked(let coachName):
                phase = .enterCode
                errorMessage = CoachConsentCopy.alreadyLinked(coach: coachName)
            }
        } catch {
            confirm.failure = .join
            phase = .groupConfirm(confirm)
        }
    }

    /// Back to the consent screen. Nothing was shared. A plan already built stays.
    func cancelGroupPlan() {
        guard !isWorking, case .groupConfirm(let confirm) = phase else { return }
        joinedCoach = nil
        errorMessage = nil
        phase = .consent(confirm.coach, athleteID: confirm.athleteID)
    }

    private func replacementSentence() async -> String? {
        guard let plan = await plans?.activePlan() else { return nil }
        let summary = GroupPlanConfirmCopy.currentPlanSummary(plan, today: now(), calendar: calendar)
        return GroupPlanConfirmCopy.replaces(summary)
    }

    private func individualFollowUp() async -> JoinCoachFollowUp {
        guard let plans, await plans.isActivePlanConfirmedMissing() else { return .today }
        return .buildMyPlan
    }

    /// Join refused because the invite moved. Show whoever the code names now, or the invalid-code copy.
    private func reshowConsent(for code: String, athleteID: UUID) async {
        do {
            if let resolved = try await repository.lookupInvite(code: code) {
                showConsent(await withConsentVersion(resolved), athleteID: athleteID)
                errorMessage = CoachConsentCopy.codeReassigned(coach: resolved.displayName)
                return
            }
        } catch {
            errorMessage = Self.message(for: error)
            phase = .enterCode
            return
        }
        phase = .enterCode
        errorMessage = CoachConsentCopy.invalidCode
    }

    static func isConsentMismatch(_ error: Error) -> Bool {
        if let service = error as? CoachLinkServiceError, case .consentMismatch = service {
            return true
        }
        let text = "\(error) \(error.localizedDescription)".lowercased()
        return text.contains("consent_mismatch")
    }

    static func message(for error: Error) -> String {
        if let service = error as? CoachLinkServiceError {
            switch service {
            case .invalidCode, .notSignedIn:
                return CoachConsentCopy.invalidCode
            case .alreadyLinked(let coachName):
                return CoachConsentCopy.alreadyLinked(coach: coachName)
            case .consentMismatch:
                return CoachConsentCopy.invalidCode
            case .offline, .notLinked:
                return CoachConsentCopy.offline
            }
        }
        let text = "\(error) \(error.localizedDescription)".lowercased()
        if text.contains("cannot_join_self") || text.contains("invalid_code") {
            return CoachConsentCopy.invalidCode
        }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return CoachConsentCopy.offline
            default:
                break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return CoachConsentCopy.offline
        }
        if text.contains("offline") || text.contains("network") || text.contains("internet") {
            return CoachConsentCopy.offline
        }
        return CoachConsentCopy.offline
    }
}

// MARK: C7.11, the coach removes an athlete (D8)

/// What `coach_remove_athlete` reported. Both mean the link is gone.
enum CoachRemoveOutcome: String, Equatable, Sendable {
    case removed
    /// The link had already ended (a retried tap, a lost response, or the athlete left first).
    case alreadyEnded = "already_ended"
}

/// The one removal line the athlete still has to see (`my_coach_link_notice`).
struct CoachLinkNotice: Equatable, Sendable, Identifiable {
    let linkID: UUID
    let coachName: String
    var id: UUID { linkID }
}

/// C7.11 RPCs. The coach removes; the removed athlete reads and clears the one-time line.
nonisolated protocol CoachLinkEndServing: Sendable {
    /// `coach_remove_athlete(p_athlete)`. No v2 gate on the server: any build can be removed.
    func removeAthlete(_ athleteID: UUID) async throws -> CoachRemoveOutcome
    /// `my_coach_link_notice()`. Nil when there is nothing to show.
    func linkNotice() async throws -> CoachLinkNotice?
    /// `mark_link_notice_seen(p_link_id)`.
    func markLinkNoticeSeen(linkID: UUID) async throws
}

nonisolated struct SupabaseCoachLinkEndService: CoachLinkEndServing {
    private struct NoticeRow: Decodable {
        let linkId: UUID
        let coachName: String

        enum CodingKeys: String, CodingKey {
            case linkId = "link_id"
            case coachName = "coach_name"
        }
    }

    func removeAthlete(_ athleteID: UUID) async throws -> CoachRemoveOutcome {
        let raw: String = try await SupabaseManager.client
            .rpc("coach_remove_athlete", params: ["p_athlete": athleteID])
            .execute()
            .value
        return CoachRemoveOutcome(rawValue: raw) ?? .removed
    }

    func linkNotice() async throws -> CoachLinkNotice? {
        let rows: [NoticeRow] = try await SupabaseManager.client
            .rpc("my_coach_link_notice")
            .execute()
            .value
        return rows.first.map { CoachLinkNotice(linkID: $0.linkId, coachName: $0.coachName) }
    }

    func markLinkNoticeSeen(linkID: UUID) async throws {
        try await SupabaseManager.client
            .rpc("mark_link_notice_seen", params: ["p_link_id": linkID])
            .execute()
    }
}

/// C7.11 copy. The athlete line is fixed by the UX spec (G16). The coach sheet lists the
/// same effects as the athlete's A13 leave sheet, from the coach's side (light copy review).
/// Names are filled with `BidiText.fill`, never concatenated (C7.15).
enum CoachRemovalCopy {
    static let offline = LeaveCoachCopy.offline
    static let cancel = "Cancel"
    static let noticeOK = "OK"

    /// The athlete's one-time line. No push carries it.
    static func notice(coach: String) -> String {
        BidiText.fill("You're no longer coached by {Coach}. Your plan stays and RunSmart keeps adapting it.",
                      ["Coach": coach])
    }

    static func menuItem(athlete: String) -> String {
        BidiText.fill("Remove {Athlete}", ["Athlete": athlete])
    }

    static func title(athlete: String) -> String {
        BidiText.fill("Remove {Athlete}?", ["Athlete": athlete])
    }

    static func failure(athlete: String) -> String {
        BidiText.fill("Couldn't remove {Athlete} right now. {Athlete} is still linked. Try again.",
                      ["Athlete": athlete])
    }

    /// Sheet body below the title.
    static func sheet(athlete: String) -> String {
        BidiText.fill("""
        {Athlete} will no longer be coached by you.

        What stops:
        • You won't see {Athlete}'s plan, runs or maps.
        • You won't see {Athlete}'s effort, notes or flags.
        • You can't review {Athlete}'s runs, send feedback or change their workouts.

        What stays:
        • {Athlete}'s plan, which RunSmart keeps adapting.
        • Feedback you already gave. {Athlete} can still read it.

        {Athlete} sees one line in the app. No notification is sent.
        {Athlete} can join you again with your code.
        """, ["Athlete": athlete])
    }
}

/// Remove confirm. Cancel calls nothing. A failed RPC keeps the athlete linked and shows the
/// error in the sheet. `already_ended` counts as done: the link is gone either way.
@MainActor
final class RemoveAthleteModel: ObservableObject {
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published var isOnline: Bool

    private let service: any CoachLinkEndServing
    private let analytics: () -> any AnalyticsTracking

    init(
        isOnline: Bool = true,
        service: any CoachLinkEndServing = SupabaseCoachLinkEndService(),
        analytics: @escaping () -> any AnalyticsTracking = { Analytics.shared }
    ) {
        self.isOnline = isOnline
        self.service = service
        self.analytics = analytics
    }

    func cancel() {
        errorMessage = nil
    }

    /// True when the link is gone. False keeps the sheet open with `errorMessage`.
    func confirm(athleteID: UUID, athleteName: String) async -> Bool {
        guard !isWorking else { return false }
        errorMessage = nil
        guard isOnline else {
            errorMessage = CoachRemovalCopy.offline
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let outcome = try await service.removeAthlete(athleteID)
            if outcome == .removed {
                CoachV2Analytics.track(.coachRemovedAthlete, to: analytics())
            }
            return true
        } catch {
            errorMessage = CoachRemovalCopy.failure(athlete: athleteName)
            return false
        }
    }
}

/// The removed athlete's one-time line (C7.11 AC5). With v2 off, while linked, or before the
/// link read finished, it shows nothing and calls nothing. It is marked seen when shown, so it
/// appears once; a failed mark shows it again on the next open.
@MainActor
final class CoachLinkNoticeModel: ObservableObject {
    @Published private(set) var notice: CoachLinkNotice?

    private let service: any CoachLinkEndServing
    private var userID: UUID?
    private var marked: Set<UUID> = []
    private var generation = 0

    init(service: any CoachLinkEndServing = SupabaseCoachLinkEndService()) {
        self.service = service
    }

    /// `noLink` is true only once the link read finished and found no active link.
    func evaluate(v2Enabled: Bool, userID: UUID?, noLink: Bool) async {
        if userID != self.userID {
            self.userID = userID
            notice = nil
            marked = []
        }
        generation += 1
        guard v2Enabled, userID != nil, noLink else {
            notice = nil
            return
        }
        guard notice == nil else { return }
        let current = generation
        let fetched = try? await service.linkNotice()
        guard current == generation, self.userID == userID else { return }
        if let fetched, !marked.contains(fetched.linkID) {
            notice = fetched
        }
    }

    /// Call when the line is on screen.
    func shown() async {
        guard let notice, !marked.contains(notice.linkID) else { return }
        marked.insert(notice.linkID)
        do {
            try await service.markLinkNoticeSeen(linkID: notice.linkID)
        } catch {
            marked.remove(notice.linkID)
        }
    }

    func dismiss() {
        notice = nil
    }
}
