import Foundation
import Combine
import Supabase

// "Coach" in this file means a HUMAN coach (Coach Mode). It is unrelated to the AI
// coach: `coach_message`, `profiles.coaching_style`, `CoachFlowView`.

struct CoachLink: Equatable, Sendable {
    let id: UUID
    let coachID: UUID
    let coachName: String
}

struct CoachLookup: Equatable, Sendable {
    let coachID: UUID
    let displayName: String
}

enum JoinCoachOutcome: Equatable, Sendable {
    case joined(CoachLookup)
    case alreadyLinked(coachName: String)
}

enum CoachLinkServiceError: Error, Equatable {
    case invalidCode
    case alreadyLinked(coachName: String)
    case offline
    case notSignedIn
}

/// Reads and creates the athlete's consent link. Later Coach Mode stories reuse this.
nonisolated protocol CoachLinkRepository: Sendable {
    func currentLink() async throws -> CoachLink?
    func lookupInvite(code: String) async throws -> CoachLookup?
    func joinCoach(code: String) async throws -> JoinCoachOutcome
}

nonisolated struct SupabaseCoachLinkRepository: CoachLinkRepository {
    private struct LookupRow: Decodable {
        let coachId: UUID
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case coachId = "coach_id"
            case displayName = "display_name"
        }
    }

    private struct LinkRow: Decodable {
        let linkId: UUID
        let coachId: UUID
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case linkId = "link_id"
            case coachId = "coach_id"
            case displayName = "display_name"
        }
    }

    private struct JoinPayload: Decodable {
        let status: String
        let coachId: UUID
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case status
            case coachId = "coach_id"
            case displayName = "display_name"
        }
    }

    private struct CodeParams: Encodable {
        let code: String
    }

    func currentLink() async throws -> CoachLink? {
        let rows: [LinkRow] = try await SupabaseManager.client
            .rpc("my_coach_link")
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return CoachLink(id: row.linkId, coachID: row.coachId, coachName: row.displayName)
    }

    func lookupInvite(code: String) async throws -> CoachLookup? {
        let rows: [LookupRow] = try await SupabaseManager.client
            .rpc("lookup_invite", params: CodeParams(code: code))
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return CoachLookup(coachID: row.coachId, displayName: row.displayName)
    }

    func joinCoach(code: String) async throws -> JoinCoachOutcome {
        let payload: JoinPayload = try await SupabaseManager.client
            .rpc("join_coach", params: CodeParams(code: code))
            .execute()
            .value
        let lookup = CoachLookup(coachID: payload.coachId, displayName: payload.displayName)
        switch payload.status {
        case "joined":
            return .joined(lookup)
        case "already_linked":
            return .alreadyLinked(coachName: payload.displayName)
        default:
            throw CoachLinkServiceError.invalidCode
        }
    }
}

/// Current link plus the coach's name. Settings uses `showsJoinCoach`.
@MainActor
final class CoachLinkStore: ObservableObject {
    @Published private(set) var currentLink: CoachLink?
    @Published private(set) var didAttemptLoad = false

    /// Kept when Continue sends a signed-out athlete to sign in, so A1 still has the code after.
    @Published var draftCode = ""
    @Published var resumeJoinAfterSignIn = false

    private let repository: any CoachLinkRepository

    init(repository: any CoachLinkRepository = SupabaseCoachLinkRepository()) {
        self.repository = repository
    }

    /// The Settings row is shown only when we know there is no active link.
    var showsJoinCoach: Bool {
        didAttemptLoad && currentLink == nil
    }

    func clear() {
        currentLink = nil
        didAttemptLoad = false
    }

    func refresh() async {
        do {
            currentLink = try await repository.currentLink()
            didAttemptLoad = true
        } catch is CancellationError {
            return
        } catch {
            // A failed read must not pretend the athlete is linked, or the row would vanish.
            didAttemptLoad = true
            print("[CoachLinkStore] current link failed:", error)
        }
    }

    func noteJoined(_ lookup: CoachLookup) {
        currentLink = CoachLink(id: UUID(), coachID: lookup.coachID, coachName: lookup.displayName)
        didAttemptLoad = true
        draftCode = ""
        resumeJoinAfterSignIn = false
    }
}

/// A1 and A3 copy. The consent sentences are the story's source of truth.
enum CoachConsentCopy {
    static let invalidCode = "That code doesn't work. Check it with your coach."
    static let offline = "You need to be online to join."

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
}

enum JoinCoachPhase: Equatable {
    case enterCode
    case consent(CoachLookup)
    case needsSignIn
}

@MainActor
final class JoinCoachViewModel: ObservableObject {
    @Published var code: String
    @Published private(set) var phase: JoinCoachPhase = .enterCode
    @Published private(set) var errorMessage: String?
    @Published private(set) var isWorking = false
    @Published private(set) var joinedCoach: CoachLookup?

    private let repository: any CoachLinkRepository
    /// The code Continue looked up. Share uses this, not the editable field.
    private var consentedCode: String?

    init(code: String = "", repository: any CoachLinkRepository = SupabaseCoachLinkRepository()) {
        self.code = code
        self.repository = repository
    }

    func continueTapped(isSignedIn: Bool) async {
        errorMessage = nil
        consentedCode = nil
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        code = trimmed
        guard !trimmed.isEmpty else {
            errorMessage = CoachConsentCopy.invalidCode
            return
        }
        guard isSignedIn else {
            phase = .needsSignIn
            return
        }

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
            consentedCode = trimmed
            phase = .consent(coach)
        } catch {
            phase = .enterCode
            errorMessage = Self.message(for: error)
        }
    }

    /// Sign-in finished or was dismissed. The code is unchanged.
    func returnedFromSignIn() {
        if phase == .needsSignIn {
            phase = .enterCode
        }
    }

    /// Not now: leave the consent screen. Does not call join.
    func notNow() {
        joinedCoach = nil
        errorMessage = nil
        consentedCode = nil
        phase = .enterCode
    }

    func share() async {
        guard case .consent = phase, let consentedCode else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await repository.joinCoach(code: consentedCode) {
            case .joined(let coach):
                joinedCoach = coach
            case .alreadyLinked(let coachName):
                phase = .enterCode
                errorMessage = CoachConsentCopy.alreadyLinked(coach: coachName)
            }
        } catch {
            let message = Self.message(for: error)
            if message == CoachConsentCopy.invalidCode || message == CoachConsentCopy.offline
                || message.hasPrefix("You're with ") {
                phase = .enterCode
            }
            errorMessage = message
        }
    }

    static func message(for error: Error) -> String {
        if let service = error as? CoachLinkServiceError {
            switch service {
            case .invalidCode, .notSignedIn:
                return CoachConsentCopy.invalidCode
            case .alreadyLinked(let coachName):
                return CoachConsentCopy.alreadyLinked(coach: coachName)
            case .offline:
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
