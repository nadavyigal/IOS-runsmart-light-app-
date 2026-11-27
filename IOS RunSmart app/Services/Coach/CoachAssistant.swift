import Foundation
import SwiftUI

/// What the AI request needs to know about the human coach. Locked ids come from the
/// active plan's `locked = true` rows (C8.5); the server re-reads them from the database.
struct CoachContext: Equatable, Sendable {
    var coachDisplayName: String
    var linkActive: Bool
    var lockedWorkoutIDs: [String]
    /// C8.5 AC 8 (G21): the athlete has an open pain flag. Sent only when true.
    var openPainFlag = false

    static let solo = CoachContext(coachDisplayName: "", linkActive: false, lockedWorkoutIDs: [])

    /// Feature-gated. A link with the flag off is solo, so Release athletes see today's AI.
    static func forRequest(
        link: CoachLink?,
        lockedWorkoutIDs: [String] = [],
        coachModeEnabled: Bool = RunSmartFeatures.coachModeEnabled
    ) -> CoachContext {
        guard coachModeEnabled, let link else { return .solo }
        let name = link.coachName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .solo }
        return CoachContext(coachDisplayName: name, linkActive: true, lockedWorkoutIDs: lockedWorkoutIDs)
    }
}

/// The app's one place services read the link without owning `CoachLinkStore`.
final class CoachContextSource: @unchecked Sendable {
    static let shared = CoachContextSource()

    private let lock = NSLock()
    private var stored = CoachContext.solo
    private var ownerID: UUID?

    private var lockedIDs: [String] = []
    private var lockedOwnerID: UUID?

    /// Solo stays `.solo` (no locked ids), so a solo request's bytes never change.
    func context(for userID: UUID?) -> CoachContext {
        lock.lock()
        defer { lock.unlock() }
        guard let userID, userID == ownerID else { return .solo }
        var context = stored
        if context.linkActive, lockedOwnerID == userID {
            context.lockedWorkoutIDs = lockedIDs
        }
        return context
    }

    func replace(_ context: CoachContext, ownerID: UUID?) {
        lock.lock()
        self.ownerID = ownerID
        stored = context
        lock.unlock()
    }

    /// Called whenever the active plan loads. Ids are lower-case, like the server's.
    func replaceLockedWorkouts(_ ids: [UUID], ownerID: UUID) {
        lock.lock()
        lockedOwnerID = ownerID
        lockedIDs = ids.map { $0.uuidString.lowercased() }.sorted()
        lock.unlock()
    }
}

enum CoachRequestJSON {
    /// Solo encoding is the encoder's own bytes. A linked coach adds `coachContext` and does not replace other keys.
    static func encode<T: Encodable>(_ value: T, coach: CoachContext) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard coach.linkActive else { return data }
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        var coachContext: [String: Any] = [
            "coachDisplayName": coach.coachDisplayName,
            "linkActive": true,
            "lockedWorkoutIds": coach.lockedWorkoutIDs,
        ]
        if coach.openPainFlag { coachContext["openPainFlag"] = true }
        object["coachContext"] = coachContext
        return try JSONSerialization.data(withJSONObject: object)
    }
}

/// Answers whether a workout is coach-locked and what the coach wrote on it.
protocol CoachLockProvider {
    func isLocked(workoutID: String) -> Bool
    func note(for workoutID: String) -> String?
}

struct UnavailableCoachLockProvider: CoachLockProvider {
    func isLocked(workoutID: String) -> Bool { false }
    func note(for workoutID: String) -> String? { nil }
}

/// C8.5: the plan rows the app already loaded. A locked row's `detail` is the coach's note.
struct WorkoutSummaryLockProvider: CoachLockProvider {
    var workouts: [WorkoutSummary]

    private func row(_ workoutID: String) -> WorkoutSummary? {
        workouts.first { $0.id.uuidString.caseInsensitiveCompare(workoutID) == .orderedSame }
    }

    func isLocked(workoutID: String) -> Bool { row(workoutID)?.coachLocked == true }

    func note(for workoutID: String) -> String? {
        guard let row = row(workoutID), row.coachLocked else { return nil }
        return row.detail
    }
}

/// Fixed copy when the athlete asks the AI to change a coach-set workout. Copy only: no chat destination.
struct CoachLockReply: Equatable {
    var message: String
    var noteLinkTitle: String?
    var note: String?
}

enum CoachLockReplyBuilder {
    /// Nil when the workout is not locked, so the caller keeps the normal AI request and changes nothing.
    static func replyIfLocked(
        coachName: String,
        workoutID: String,
        provider: CoachLockProvider
    ) -> CoachLockReply? {
        guard provider.isLocked(workoutID: workoutID) else { return nil }
        let trimmed = provider.note(for: workoutID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (trimmed?.isEmpty == false) ? trimmed : nil
        return CoachLockReply(
            message: "That's \(coachName)'s workout.",
            noteLinkTitle: note == nil ? nil : "Read \(coachName)'s note",
            note: note
        )
    }
}

struct CoachLockReplyView: View {
    var reply: CoachLockReply
    @State private var showsNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reply.message)
            if let title = reply.noteLinkTitle, reply.note != nil {
                Button(title) { showsNote = true }
                    .buttonStyle(.plain)
            }
            if showsNote, let note = reply.note {
                Text(note)
            }
        }
        .accessibilityIdentifier("coachLock.reply")
    }
}

private struct CoachAssistantActiveKey: EnvironmentKey {
    static let defaultValue = false
}

private struct CoachAssistantNameKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    var coachAssistantActive: Bool {
        get { self[CoachAssistantActiveKey.self] }
        set { self[CoachAssistantActiveKey.self] = newValue }
    }

    var coachAssistantName: String {
        get { self[CoachAssistantNameKey.self] }
        set { self[CoachAssistantNameKey.self] = newValue }
    }
}

/// Static strings that call the AI engine a coach. Solo keeps today's wording. The human coach's own strings are not in `swaps`.
enum CoachAssistantCopy {
    struct Swap: Equatable, Identifiable {
        let id: String
        let solo: String
        let linked: String
    }

    static let swaps: [Swap] = [
        Swap(id: "plan.upcoming", solo: "Upcoming from Your Coach", linked: "Upcoming workouts in RunSmart"),
        Swap(id: "share.insight", solo: "Include coach insight", linked: "Include RunSmart insight"),
        Swap(id: "profile.section", solo: "Your AI Coach", linked: "RunSmart"),
        Swap(id: "cues.toggle", solo: "Extra AI coach cues", linked: "Extra RunSmart cues"),
        Swap(id: "run.saved", solo: "Run saved. Great work - your coach will factor this into the plan.", linked: "Run saved. Great work - RunSmart will factor this into the plan."),
        Swap(id: "training.baseline", solo: "Save the baseline your coach uses to size training load.", linked: "Save the baseline RunSmart uses to size training load."),
        Swap(id: "plan.logic", solo: "Coach logic for safe plan changes.", linked: "RunSmart logic for safe plan changes."),
        Swap(id: "tone.subtitle", solo: "Pick the coach personality for future guidance.", linked: "Pick the RunSmart tone for future guidance."),
        Swap(id: "goal.subtitle", solo: "Tell the coach what to optimize this block around.", linked: "Tell RunSmart what to optimize this block around."),
        Swap(id: "adaptive.label", solo: "ADAPTIVE COACH", linked: "RUNSMART"),
        Swap(id: "adaptive.dismiss", solo: "Dismiss adaptive coach suggestion", linked: "Dismiss RunSmart suggestion"),
        Swap(id: "week.ask", solo: "Ask Coach", linked: "Ask RunSmart"),
        Swap(id: "chat.field", solo: "Ask Coach anything...", linked: "Ask RunSmart anything..."),
        Swap(id: "chat.empty", solo: "No verified coach conversation yet. Ask a question to start a new thread with your current RunSmart context.", linked: "No verified RunSmart conversation yet. Ask a question to start a new thread with your current RunSmart context."),
        Swap(id: "chat.preparing", solo: "Preparing Coach context", linked: "Preparing RunSmart context"),
        Swap(id: "report.empty", solo: "Complete a run and tap Generate to get your first AI coach report.", linked: "Complete a run and tap Generate to get your first RunSmart report."),
        Swap(id: "flex.talk.body", solo: "Want to talk through what's going on? Coach can look at the full picture and suggest a more sustainable approach.", linked: "Want to talk through what's going on? RunSmart can look at the full picture and suggest a more sustainable approach."),
        Swap(id: "flex.talk.button", solo: "Talk to Coach", linked: "Talk to RunSmart"),
        Swap(id: "workout.actions", solo: "Coach Actions", linked: "RunSmart actions"),
        Swap(id: "workout.adjust", solo: "Ask the coach to reshuffle the week.", linked: "Ask RunSmart to reshuffle the week."),
        Swap(id: "sync.canUse", solo: "Coach can now use", linked: "RunSmart can now use"),
        Swap(id: "plan.building", solo: "Coach is building your plan", linked: "RunSmart is building your plan"),
        Swap(id: "plan.missing", solo: "Your goal and schedule are saved. Tap Build my plan and the coach will turn them into a week-by-week plan.", linked: "Your goal and schedule are saved. Tap Build my plan and RunSmart will turn them into a week-by-week plan."),
        Swap(id: "debrief.reaction", solo: "COACH REACTION", linked: "RUNSMART"),
        Swap(id: "debrief.learned", solo: "COACH LEARNED", linked: "RUNSMART"),
        Swap(id: "debrief.learnedLine", solo: "What Coach learned", linked: "What RunSmart learned"),
        Swap(id: "debrief.section", solo: "COACH", linked: "RUNSMART"),
        Swap(id: "report.notes", solo: "Coach Notes", linked: "RunSmart notes"),
        Swap(id: "report.pending", solo: "Coach Report", linked: "RunSmart report"),
        Swap(id: "report.missing", solo: "This is a real activity, but no generated coach report has been saved yet.", linked: "This is a real activity, but no generated RunSmart report has been saved yet."),
        Swap(id: "flex.careful", solo: "Coach is taking a careful path — here's a safe adjustment based on standard recovery rules.", linked: "RunSmart is taking a careful path — here's a safe adjustment based on standard recovery rules."),
    ]

    /// Strings that mean the human coach. They stay as they are while a link is active.
    static let humanCoachStrings = [
        "Enter your coach's code.",
        "Sign in first. Then you'll enter your coach's code.",
        "That code doesn't work. Check it with your coach.",
    ]

    static func apply(_ solo: String, assistant: Bool) -> String {
        guard assistant, let swap = swaps.first(where: { $0.solo == solo }) else { return solo }
        return swap.linked
    }

    static func flexCarefulPath(assistant: Bool) -> String {
        apply(swaps.first { $0.id == "flex.careful" }?.solo ?? "", assistant: assistant)
    }

    static func chatPrivacy(coachName: String) -> String {
        "Private to you. \(coachName) can't see this chat."
    }

    static let debriefPrivacy = "RunSmart's notes · private to you"
}
