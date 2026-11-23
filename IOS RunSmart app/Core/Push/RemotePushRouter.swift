import Foundation

// Remote push tap routing (Coach Experience v2, story C7.10 AC8, v1.3 §3.5).
// "Coach" means a HUMAN coach (Coach Mode), not the AI coach.
//
// The server sends each push with one custom object, "rs" (supabase/functions/_shared/apns.ts):
//   { "v": 1, "kind": "<kind>", "athlete_id": ..., "day": "yyyy-MM-dd", "flag_id": ..., ... }
// Only ids and days travel in it: never a note, flag or reply text.
//
// `RemotePushRouter.route` is pure: it takes the payload and what the app knows right now, and
// returns where to open plus an optional one-line notice. When the target is gone (link ended,
// workout deleted, flag resolved) it opens the nearest valid screen with the notice. When the app
// does not know yet (roster not loaded), it opens the nearest safe screen with no notice, so it
// never claims something is gone that may not be.

/// The §3.5 kinds, plus `selfTest` (push_selftest). Raw values match `REMOTE_PUSH_KINDS` in apns.ts.
nonisolated enum RemotePushKind: String, CaseIterable, Sendable {
    case coachRunFinished
    case coachEveningSummary
    case coachPainFlag
    case athleteCoachNote
    /// The coach receives it: an athlete replied to the coach's note.
    case athleteCoachReply
    case athletePlanPublished
    case athletePlanUpdated
    case athleteBroadcast
    case selfTest
}

nonisolated struct RemotePushPayload: Equatable, Sendable {
    let kind: RemotePushKind
    var athleteID: UUID?
    var coachID: UUID?
    /// `yyyy-MM-dd`, the athlete's day.
    var day: String?
    var runID: String?
    var flagID: UUID?
    var feedbackID: UUID?
    var workoutID: UUID?

    init(kind: RemotePushKind, athleteID: UUID? = nil, coachID: UUID? = nil, day: String? = nil,
         runID: String? = nil, flagID: UUID? = nil, feedbackID: UUID? = nil, workoutID: UUID? = nil) {
        self.kind = kind
        self.athleteID = athleteID
        self.coachID = coachID
        self.day = day
        self.runID = runID
        self.flagID = flagID
        self.feedbackID = feedbackID
        self.workoutID = workoutID
    }

    /// Nil for a local reminder, an unknown kind or a payload without "rs".
    init?(userInfo: [AnyHashable: Any]) {
        guard let rs = userInfo["rs"] as? [String: Any],
              let rawKind = rs["kind"] as? String,
              let kind = RemotePushKind(rawValue: rawKind) else { return nil }
        self.kind = kind
        athleteID = Self.uuid(rs["athlete_id"])
        coachID = Self.uuid(rs["coach_id"])
        day = (rs["day"] as? String).flatMap { Self.isDay($0) ? $0 : nil }
        runID = (rs["run_id"] as? String).flatMap { $0.allSatisfy(\.isNumber) && !$0.isEmpty ? $0 : nil }
        flagID = Self.uuid(rs["flag_id"])
        feedbackID = Self.uuid(rs["feedback_id"])
        workoutID = Self.uuid(rs["workout_id"])
    }

    private static func uuid(_ value: Any?) -> UUID? {
        (value as? String).flatMap(UUID.init(uuidString:))
    }

    private static func isDay(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }
}

/// What the app knows at tap time. A nil collection means "not loaded": the router then never
/// says the target is gone.
nonisolated struct RemotePushRouteContext: Equatable, Sendable {
    var v2Enabled: Bool
    var isCoach: Bool
    /// The coach's active athletes, id to display name. Nil while the roster has not loaded.
    var activeAthletes: [UUID: String]?
    /// Open flag ids the coach can see. Nil while flags have not loaded.
    var openFlagIDs: Set<UUID>?
    /// The athlete's coach link. Nil while the link store has not loaded.
    var hasActiveCoachLink: Bool?
    var coachName: String?
    /// Note ids the athlete has. Nil while notes have not loaded.
    var feedbackIDs: Set<UUID>?
    /// Planned workout ids on this device. Nil when unknown.
    var workoutIDs: Set<UUID>?

    init(v2Enabled: Bool, isCoach: Bool = false, activeAthletes: [UUID: String]? = nil,
         openFlagIDs: Set<UUID>? = nil, hasActiveCoachLink: Bool? = nil, coachName: String? = nil,
         feedbackIDs: Set<UUID>? = nil, workoutIDs: Set<UUID>? = nil) {
        self.v2Enabled = v2Enabled
        self.isCoach = isCoach
        self.activeAthletes = activeAthletes
        self.openFlagIDs = openFlagIDs
        self.hasActiveCoachLink = hasActiveCoachLink
        self.coachName = coachName
        self.feedbackIDs = feedbackIDs
        self.workoutIDs = workoutIDs
    }
}

nonisolated enum RemotePushDestination: Equatable, Sendable {
    case today
    case plan
    case coachToday
    /// The athlete detail, opened on `dayISO` when given.
    case coachAthlete(id: UUID, name: String, dayISO: String?)
    case myCoach
}

nonisolated struct RemotePushRoute: Equatable, Sendable {
    let destination: RemotePushDestination
    var notice: String?
}

/// One-line notices for a gone target. The athlete line is the UX spec's example (Part 2 › C7.10);
/// the others follow it. [ASSUMPTION copy; Sally light review]
nonisolated enum RemotePushCopy {
    static func athleteGone(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "This athlete is no longer linked to you." }
        return BidiText.fill("{Athlete} is no longer linked to you.", ["Athlete": name])
    }

    static let flagHandled = "This flag was already marked handled."
    static let workoutChanged = "This workout was changed."
    static let noteGone = "This note is no longer available."

    static func coachLinkEnded(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "You're no longer linked to this coach." }
        return BidiText.fill("You're no longer linked to {Coach}.", ["Coach": name])
    }

    // T6, UX spec §A.6 (exact strings).
    static let coachPrimerTitle = "Know when your athletes run"
    static let coachPrimerBody = "Get a ping when someone finishes a run or flags pain, and a summary at 20:00."
    // P10, UX spec §C.5 (exact strings).
    static func athletePrimerTitle(coach: String) -> String {
        BidiText.fill("Get {Coach}'s notes and plan updates", ["Coach": coach])
    }

    static func athletePrimerBody(coach: String) -> String {
        BidiText.fill("We'll only notify you when {Coach} writes to you or changes your plan.", ["Coach": coach])
    }

    static let turnOn = "Turn on"
    static let notNow = "Not now"
}

nonisolated enum RemotePushRouter {
    static func route(_ payload: RemotePushPayload, context: RemotePushRouteContext) -> RemotePushRoute {
        // Flag off: no v2 screen and no v2 string. Open the app's home as a local reminder would.
        guard context.v2Enabled else { return RemotePushRoute(destination: .today) }

        switch payload.kind {
        case .selfTest:
            return RemotePushRoute(destination: .today)

        // Coach side ----------------------------------------------------------------
        case .coachEveningSummary:
            return RemotePushRoute(destination: context.isCoach ? .coachToday : .today)

        case .coachRunFinished:
            return coachAthlete(payload, context: context, dayISO: payload.day)

        case .athleteCoachReply:
            // The reply thread lives on the athlete detail, under the note.
            return coachAthlete(payload, context: context, dayISO: nil)

        case .coachPainFlag:
            let route = coachAthlete(payload, context: context, dayISO: payload.day)
            guard case .coachAthlete = route.destination,
                  let flagID = payload.flagID, let open = context.openFlagIDs, !open.contains(flagID) else {
                return route
            }
            return RemotePushRoute(destination: route.destination, notice: RemotePushCopy.flagHandled)

        // Athlete side ------------------------------------------------------------------
        case .athleteCoachNote:
            switch context.hasActiveCoachLink {
            case false?:
                return RemotePushRoute(destination: .today, notice: RemotePushCopy.coachLinkEnded(context.coachName))
            case nil:
                return RemotePushRoute(destination: .today)
            case true?:
                if let id = payload.feedbackID, let notes = context.feedbackIDs, !notes.contains(id) {
                    return RemotePushRoute(destination: .myCoach, notice: RemotePushCopy.noteGone)
                }
                return RemotePushRoute(destination: .myCoach)
            }

        case .athletePlanPublished:
            // The plan stays the athlete's after a link ends, so Plan is always valid.
            return RemotePushRoute(destination: .plan)

        case .athletePlanUpdated:
            if let id = payload.workoutID, let workouts = context.workoutIDs, !workouts.contains(id) {
                return RemotePushRoute(destination: .plan, notice: RemotePushCopy.workoutChanged)
            }
            if context.hasActiveCoachLink == false {
                return RemotePushRoute(destination: .plan, notice: RemotePushCopy.coachLinkEnded(context.coachName))
            }
            // The change-list card (P2) lives on Today.
            return RemotePushRoute(destination: .today)

        case .athleteBroadcast:
            if context.hasActiveCoachLink == false {
                return RemotePushRoute(destination: .today, notice: RemotePushCopy.coachLinkEnded(context.coachName))
            }
            return RemotePushRoute(destination: .today)
        }
    }

    /// A coach push about one athlete. Not a coach (another account on this device): Today, no
    /// notice. Roster not loaded: Coach Today, no notice. Athlete not on the roster: Coach Today
    /// with "{Athlete} is no longer linked to you."
    private static func coachAthlete(
        _ payload: RemotePushPayload, context: RemotePushRouteContext, dayISO: String?
    ) -> RemotePushRoute {
        guard context.isCoach else { return RemotePushRoute(destination: .today) }
        guard let athleteID = payload.athleteID, let roster = context.activeAthletes else {
            return RemotePushRoute(destination: .coachToday)
        }
        guard let name = roster[athleteID] else {
            return RemotePushRoute(destination: .coachToday, notice: RemotePushCopy.athleteGone(nil))
        }
        return RemotePushRoute(destination: .coachAthlete(id: athleteID, name: name, dayISO: dayISO))
    }
}
