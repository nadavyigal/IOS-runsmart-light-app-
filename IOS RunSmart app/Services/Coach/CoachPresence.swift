import Combine
import Foundation
import Supabase

// Story 3.3. "Coach" here is a HUMAN coach (Coach Mode), not the AI coach.
//
// CoachPresence is the one gate every coach element on Today and the Plan reads. It is
// active only while CoachLinkStore holds an active link. Unlinked, revoked or left:
// inactive, and nothing coach-related renders. Later stories (3.4, 4.3, 5.2, 5.4) read
// the same gate through `CoachLayerHooks`.

/// The caller's active coach as `get_my_coach()` returns it.
nonisolated struct MyCoach: Equatable, Sendable {
    let coachID: UUID
    let displayName: String
    /// Nil while the coach hasn't chosen a Plan Mode.
    let planMode: CoachPlanMode?
}

nonisolated protocol MyCoachFetching: Sendable {
    func myCoach() async throws -> MyCoach?
}

nonisolated struct SupabaseMyCoachService: MyCoachFetching {
    private struct Row: Decodable {
        let coachId: UUID
        let displayName: String
        let planMode: String?

        enum CodingKeys: String, CodingKey {
            case coachId = "coach_id"
            case displayName = "display_name"
            case planMode = "plan_mode"
        }
    }

    func myCoach() async throws -> MyCoach? {
        let rows: [Row] = try await SupabaseManager.client.rpc("get_my_coach").execute().value
        return rows.first.map {
            MyCoach(coachID: $0.coachId, displayName: $0.displayName,
                    planMode: $0.planMode.flatMap(CoachPlanMode.init(rawValue:)))
        }
    }
}

/// The gate. Follows `CoachLinkStore.currentLink`; asks `get_my_coach()` only for the
/// Plan Mode. The coach's name always comes from the link, so the strip shows at once.
@MainActor
final class CoachPresence: ObservableObject {
    /// Nil means no coach UI anywhere.
    @Published private(set) var coach: CoachLink?
    /// Nil until known. An unknown mode keeps the solo plan title (strip only).
    @Published private(set) var planMode: CoachPlanMode?

    private let fetcher: any MyCoachFetching
    private var cancellable: AnyCancellable?
    /// Bumped on every link change, so an older Plan Mode read never applies.
    private var generation = 0
    private var modeTask: Task<Void, Never>?
    /// True once `get_my_coach()` answered for the current coach. A failed read stays
    /// false, so the next link refresh (for example on foregrounding) asks again.
    private var modeResolved = false
    private var modeInFlight = false

    init(fetcher: any MyCoachFetching = SupabaseMyCoachService()) {
        self.fetcher = fetcher
    }

    /// The app binds the gate to its link store once. Every refresh is passed on, even an
    /// unchanged link, so an unresolved Plan Mode is retried.
    func bind(to links: CoachLinkStore) {
        guard cancellable == nil else { return }
        // The store is main-actor bound and publishes on the main thread, so a leave
        // clears the gate in the same update.
        cancellable = links.$currentLink
            .sink { [weak self] link in
                MainActor.assumeIsolated { self?.apply(link) }
            }
    }

    var isActive: Bool { coach != nil }
    var coachName: String? { coach?.coachName }

    /// Applies a link change. Leaving clears everything at once, before any network call.
    /// The same link again only retries a Plan Mode read that hasn't succeeded yet.
    func apply(_ link: CoachLink?) {
        if link == coach {
            if let link, !modeResolved, !modeInFlight { fetchPlanMode(for: link) }
            return
        }
        generation += 1
        modeTask?.cancel()
        modeInFlight = false
        let sameCoach = link?.coachID == coach?.coachID
        coach = link
        if !sameCoach {
            planMode = nil
            modeResolved = false
        }
        guard let link else { return }
        fetchPlanMode(for: link)
    }

    private func fetchPlanMode(for link: CoachLink) {
        let request = generation
        modeInFlight = true
        modeTask = Task { [fetcher] in
            let fetched = try? await fetcher.myCoach()
            guard !Task.isCancelled, request == self.generation, self.coach?.id == link.id else { return }
            self.modeInFlight = false
            // Only trust the answer for this same coach.
            if let fetched, fetched.coachID == link.coachID {
                self.planMode = fetched.planMode
                self.modeResolved = true
            }
        }
    }

    /// Tests wait on the Plan Mode read.
    func waitForPlanMode() async {
        await modeTask?.value
    }
}

/// Story 3.3 copy. `{Coach}` is the coach's display name.
enum CoachPresenceCopy {
    static func coachedBy(_ coach: String) -> String { "Coached by \(coach)" }
    static func runCard(_ coach: String, weekday: String?) -> String {
        guard let weekday else { return "\(coach) on your run" }
        return "\(coach) on your \(weekday) run"
    }
    static func weekCard(_ coach: String) -> String { "\(coach)'s note for this week" }
    static func more(_ count: Int, coach: String) -> String { "\(count) more from \(coach)" }
    static func refreshFailed(_ coach: String) -> String { "Couldn't refresh \(coach)'s updates" }
    static let read = "Read"
    static let retry = "Retry"
    static func groupTitle(_ coach: String, goal: String) -> String { "\(coach)'s plan: \(goal)" }
    static func groupTitleNoGoal(_ coach: String) -> String { "\(coach)'s plan" }
    static func individualTitle(_ coach: String) -> String { "\(coach)'s plan for you" }
    static func individualSubline(_ coach: String) -> String { "RunSmart builds it, \(coach) supervises it" }
    static func customGoalTitle(_ coach: String, goal: String) -> String { "\(coach)'s plan for you: \(goal)" }
}

// MARK: - Today (A5)

/// One coach card on Today. Unread notes only, newest first.
struct TodayCoachCard: Equatable, Identifiable {
    let note: AthleteFeedbackNote
    let title: String
    var id: UUID { note.id }
}

/// Everything coach-related Today shows, or nil for no coach UI at all.
struct TodayCoachLayer: Equatable {
    enum Status: Equatable { case ready, loading, failed }

    static let maxCards = 2

    let coachName: String
    /// At most two, newest first.
    let cards: [TodayCoachCard]
    /// Unread notes past the first two. Shown as one "N more from {Coach}" row.
    let moreCount: Int
    let status: Status

    /// `runs` lets a run note name its weekday ("Saturday"). A run not on this phone
    /// falls back to "{Coach} on your run".
    static func make(
        coach: CoachLink?,
        notes: [AthleteFeedbackNote],
        loadState: AthleteFeedbackStore.LoadState,
        runs: [RecordedRun],
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> TodayCoachLayer? {
        guard let coach else { return nil }
        let unread = notes
            .filter { $0.coachID == coach.coachID && $0.createdAt >= coach.consentedAt && $0.readAt == nil }
            .sorted { $0.createdAt > $1.createdAt }
        let cards = unread.prefix(maxCards).map { note in
            TodayCoachCard(note: note, title: title(for: note, coach: coach.coachName, runs: runs,
                                                    calendar: calendar, locale: locale))
        }
        let status: Status
        switch loadState {
        case .failed: status = .failed
        // A skeleton only while nothing is known yet. Cached cards show during a refresh.
        case .loading, .idle: status = unread.isEmpty ? .loading : .ready
        case .loaded: status = .ready
        }
        return TodayCoachLayer(coachName: coach.coachName, cards: Array(cards),
                               moreCount: max(0, unread.count - maxCards), status: status)
    }

    static func title(for note: AthleteFeedbackNote, coach: String, runs: [RecordedRun],
                      calendar: Calendar, locale: Locale) -> String {
        guard note.isRunNote else { return CoachPresenceCopy.weekCard(coach) }
        let run = runs.first { note.matches($0) }
        return CoachPresenceCopy.runCard(coach, weekday: run.map { weekday($0.startedAt, calendar: calendar, locale: locale) })
    }

    static func weekday(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: date)
    }
}

/// Where Read on a Today card goes: the run's detail, or the note's week in the Plan.
enum CoachNoteDestination: Equatable {
    case run
    case week(Date?)

    static func of(_ note: AthleteFeedbackNote, calendar: Calendar = .current) -> CoachNoteDestination {
        note.isRunNote ? .run : .week(note.weekStartDate(calendar: calendar))
    }
}

// MARK: - Plan header (A6)

/// The coach plan title. `customGoal` arrives with Story 4.4 and is unused until then.
enum CoachPlanTitle: Equatable {
    case group(goal: String?)
    case individual
    case customGoal(goal: String)
}

/// The Plan header while linked, or nil for the solo header.
struct PlanCoachHeader: Equatable {
    let coachName: String
    /// Nil while the Plan Mode is unknown: the strip shows over the solo title.
    let title: CoachPlanTitle?

    static func make(coach: CoachLink?, planMode: CoachPlanMode?, goal: String?) -> PlanCoachHeader? {
        guard let coach else { return nil }
        let trimmedGoal = goal?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usableGoal = (trimmedGoal?.isEmpty ?? true) ? nil : trimmedGoal
        let title: CoachPlanTitle? = switch planMode {
        case .group: .group(goal: usableGoal)
        case .individual: .individual
        case nil: nil
        }
        return PlanCoachHeader(coachName: coach.coachName, title: title)
    }

    var titleText: String? {
        switch title {
        case .group(let goal?): CoachPresenceCopy.groupTitle(coachName, goal: goal)
        case .group(nil): CoachPresenceCopy.groupTitleNoGoal(coachName)
        case .individual: CoachPresenceCopy.individualTitle(coachName)
        case .customGoal(let goal): CoachPresenceCopy.customGoalTitle(coachName, goal: goal)
        case nil: nil
        }
    }

    var sublineText: String? {
        title == .individual ? CoachPresenceCopy.individualSubline(coachName) : nil
    }
}

// MARK: - Hooks for later stories (no UI yet)

/// Places later stories add to the coach layer. Each reads `CoachPresence`, so all of it
/// disappears when the athlete leaves. None of them shows anything yet.
enum CoachLayerHooks {
    /// Story 3.4: the coach's welcome note, the top Today card on the first Today.
    /// Arrives as a `kind = 'welcome'` feedback row and joins `TodayCoachLayer.cards`.
    static func showsWelcomeCard(_ presence: CoachPresence) -> Bool {
        guard presence.isActive else { return false }
        return false
    }

    /// Stories 4.3 and 5.2: the "{Coach} updated your plan" card on Today, and the
    /// "Edited by {Coach}" label on Plan rows and workout detail.
    static func showsPlanUpdateCard(_ presence: CoachPresence) -> Bool {
        guard presence.isActive else { return false }
        return false
    }

    static func editedByLabel(_ presence: CoachPresence, workout: WorkoutSummary) -> String? {
        guard presence.isActive else { return nil }
        return nil
    }

    /// Story 5.4: the coach's praise card on Today.
    static func showsPraiseCard(_ presence: CoachPresence) -> Bool {
        guard presence.isActive else { return false }
        return false
    }
}
