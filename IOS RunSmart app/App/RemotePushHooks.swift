import SwiftUI

/// C7.10: wires `RemotePushRegistrar` to the shell. Renders nothing.
/// - Passes the signed-in user and the v2 gate to the registrar, and runs its foreground work.
/// - T6 moment: the Coach tab (Coach Today) is open with v2 on (AC2).
/// - P10 moment: the athlete tapped OK on P8 or P9 (AC3).
/// - Remote push taps: builds what the app knows now and opens the route (AC8).
/// With v2 off the registrar does nothing, so these hooks make no server call and show nothing.
struct RemotePushHooks: View {
    @ObservedObject var gate: CoachV2Gate
    @ObservedObject var router: AppRouter
    @ObservedObject var coachMode: CoachModeStore
    let athletes: CoachAthleteListModel
    @ObservedObject var coachLinks: CoachLinkStore
    let feedback: AthleteFeedbackStore
    let userID: UUID?
    var registrar: RemotePushRegistrar = .shared
    @Environment(\.scenePhase) private var scenePhase

    private var sessionKey: String {
        "\(userID?.uuidString ?? "-").\(gate.isEnabled)"
    }

    private var coachTodayKey: String {
        "\(sessionKey).\(router.selectedTab == .coach).\(coachMode.isCoach)"
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task {
                guard !RunSmartDemoMode.isEnabled else { return }
                PushService.shared.configureRemoteTaps { payload in
                    Task { await open(payload) }
                }
            }
            .task(id: sessionKey) {
                guard !RunSmartDemoMode.isEnabled else { return }
                registrar.update(userID: userID, v2Enabled: gate.isEnabled)
                await registrar.foreground()
            }
            .task(id: coachTodayKey) {
                guard !RunSmartDemoMode.isEnabled, gate.isEnabled, coachMode.isCoach,
                      router.selectedTab == .coach else { return }
                await registrar.coachTodayOpened()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !RunSmartDemoMode.isEnabled else { return }
                Task { await registrar.foreground() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .remotePushAthleteContext)) { note in
                guard !RunSmartDemoMode.isEnabled, let coachName = note.object as? String else { return }
                Task { await registrar.athleteConsentAcknowledged(coachName: coachName) }
            }
    }

    private func open(_ payload: RemotePushPayload) async {
        // A coach push before the roster loaded (cold launch): load it once so the router can tell
        // "gone" from "not loaded yet".
        if gate.isEnabled, coachMode.isCoach, Self.isCoachKind(payload.kind), let userID,
           athletes.ownerID != userID || athletes.updatedAt == nil {
            await athletes.refresh(owner: userID)
        }
        let route = registrar.route(for: payload, context: context)
        router.openRemotePush(route.destination)
    }

    private var context: RemotePushRouteContext {
        let rosterLoaded = userID != nil && athletes.ownerID == userID && athletes.updatedAt != nil
        let today = athletes.today
        return RemotePushRouteContext(
            v2Enabled: gate.isEnabled,
            isCoach: coachMode.isCoach,
            activeAthletes: rosterLoaded
                ? Dictionary(athletes.rows.map { ($0.id, $0.athlete.displayName) }, uniquingKeysWith: { first, _ in first })
                : nil,
            openFlagIDs: today.flatMap { $0.flagsLoaded ? Set($0.rows.flatMap { $0.flags.map(\.id) }) : nil },
            hasActiveCoachLink: coachLinks.didAttemptLoad ? coachLinks.activeLink(for: userID) != nil : nil,
            coachName: coachLinks.currentLink?.coachName,
            feedbackIDs: feedback.loadState == .loaded ? Set(feedback.notes.map(\.id)) : nil,
            workoutIDs: nil
        )
    }

    private static func isCoachKind(_ kind: RemotePushKind) -> Bool {
        switch kind {
        case .coachRunFinished, .coachPainFlag, .athleteCoachReply, .coachEveningSummary, .coachDigest: true
        default: false
        }
    }
}
