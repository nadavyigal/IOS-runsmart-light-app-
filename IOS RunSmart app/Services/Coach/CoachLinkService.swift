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
}

nonisolated struct SupabaseCoachLinkRepository: CoachLinkRepository {
    private struct LookupRow: Decodable {
        let inviteId: UUID
        let coachId: UUID
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case inviteId = "invite_id"
            case coachId = "coach_id"
            case displayName = "display_name"
        }
    }

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

    func currentLink() async throws -> CoachLink? {
        let rows: [LinkRow] = try await SupabaseManager.client
            .rpc("my_coach_link")
            .execute()
            .value
        return rows.first?.link
    }

    func lookupInvite(code: String) async throws -> CoachLookup? {
        let rows: [LookupRow] = try await SupabaseManager.client
            .rpc("lookup_invite", params: CodeParams(code: code))
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return CoachLookup(
            inviteID: row.inviteId,
            coachID: row.coachId,
            displayName: row.displayName,
            code: code
        )
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
    /// `coachWorkoutLocksEnabled` is true.
    static func sheet(coach: String) -> String {
        var stops = [
            "• \(coach) won't see your plan, runs or maps.",
            "• \(coach) won't review your runs or send new feedback.",
            "• \(coach) can't change your workouts.",
        ]
        if coachWorkoutLocksEnabled {
            stops.append("• Workouts \(coach) set are no longer protected, so RunSmart may adjust them.")
        }
        stops.append("• \(coach)'s name and notes are removed from your plan.")
        let stopBlock = stops.joined(separator: "\n")
        return """
        \(title(coach: coach))
        If you leave, \(coach) will no longer see your runs.

        What stops:
        \(stopBlock)

        What stays:
        • Your plan, which RunSmart keeps adapting.
        • Your run history.
        • Feedback \(coach) has already given you. You can still read it on the runs it was written for.

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

    init(isOnline: Bool = true) {
        self.isOnline = isOnline
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
}

@MainActor
final class JoinCoachViewModel: ObservableObject {
    @Published var code: String
    @Published private(set) var phase: JoinCoachPhase = .enterCode
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published private(set) var joinedCoach: CoachLink?
    /// A2 hint. The typed-code field does not show this on its own.
    @Published private(set) var showsEntryHint = false

    private let repository: any CoachLinkRepository

    init(code: String = "", repository: any CoachLinkRepository = SupabaseCoachLinkRepository()) {
        self.code = code
        self.repository = repository
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
            phase = .consent(coach, athleteID: athleteID)
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
            phase = .consent(coach, athleteID: athleteID)
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
                phase = .consent(resolved, athleteID: athleteID)
                errorMessage = CoachConsentCopy.codeReassigned(coach: resolved.displayName)
                return
            }
            switch try await repository.joinCoach(
                code: shown.code,
                inviteID: shown.inviteID,
                coachID: shown.coachID,
                athleteID: consentingAthleteID
            ) {
            case .joined(let coach):
                joinedCoach = coach
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

    /// Join refused because the invite moved. Show whoever the code names now, or the invalid-code copy.
    private func reshowConsent(for code: String, athleteID: UUID) async {
        do {
            if let resolved = try await repository.lookupInvite(code: code) {
                phase = .consent(resolved, athleteID: athleteID)
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
