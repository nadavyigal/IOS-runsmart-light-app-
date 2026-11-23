import Network
import SwiftUI

/// A11 My coach, and A13 leave confirm. Human coach only.
struct MyCoachView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SupabaseSession
    @EnvironmentObject private var coachLinks: CoachLinkStore
    @EnvironmentObject private var feedback: AthleteFeedbackStore
    @EnvironmentObject private var router: AppRouter
    @Environment(\.runSmartServices) private var services

    @ObservedObject private var routes = CoachRouteOutbox.shared
    @StateObject private var model = LeaveCoachModel()
    @State private var showLeaveSheet = false
    @State private var pathMonitor: NWPathMonitor?
    @State private var openTask: Task<Void, Never>?
    @State private var unavailableNoteID: UUID?
    /// C7.8 AC8: the leave sheet adds its v2 lines only while v2 is on and the link is v2.
    @State private var leaveIncludesV2Lines = false

    var body: some View {
        Group {
            if let link = coachLinks.currentLink {
                coach(link)
            } else {
                Text("Join a coach")
                    .font(.body.weight(.semibold))
            }
        }
        .onAppear(perform: startReachability)
        .task(id: coachLinks.currentLink?.id) { await loadLeaveV2Lines() }
        .onDisappear {
            stopReachability()
            // A report must not open after My coach is closed.
            openTask?.cancel()
            openTask = nil
        }
        .sheet(isPresented: $showLeaveSheet) {
            if let link = coachLinks.currentLink {
                LeaveCoachSheet(coachName: link.coachName, model: model,
                                includesV2Lines: leaveIncludesV2Lines) {
                    guard let userID = session.currentUserID else { return }
                    let toast = await model.confirm(
                        coachName: link.coachName,
                        userID: userID,
                        store: coachLinks,
                        expectedLinkID: link.id
                    )
                    if toast != nil {
                        showLeaveSheet = false
                        dismiss()
                    }
                }
            }
        }
    }

    /// A11 Feedback row: every note from this coach since joining, newest first. Each opens
    /// its run or week. The welcome remains readable here while linked.
    private func feedbackList(_ link: CoachLink) -> some View {
        let notes = feedback.currentNotes(link: link)
        return VStack(alignment: .leading, spacing: 8) {
            Text(AthleteFeedbackCopy.feedbackRow)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if notes.isEmpty {
                switch feedback.loadState {
                case .failed:
                    AthleteFeedbackError(coachName: link.coachName) { Task { await feedback.load() } }
                case .idle, .loading:
                    AthleteFeedbackSkeleton()
                case .loaded:
                    Text("No notes from \(link.coachName) yet.")
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            ForEach(notes) { note in
                if note.kind == .welcome {
                    CoachSignedCard(title: CoachPresenceCopy.welcomeCard(note.coachName), text: note.text,
                                    coachName: note.coachName) {
                        if note.readAt == nil {
                            Button(CoachPresenceCopy.read) { Task { await feedback.markRead([note]) } }
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityHint("Marks the welcome as read")
                        }
                        // C7.7: the welcome is a coach_feedback row, so it takes replies (v2 only).
                        FeedbackReplyThread(note: note, link: link)
                    }
                } else {
                    Button { open(note) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(verbatim: AthleteFeedbackFormat.header(note))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                                if note.readAt == nil {
                                    Circle().fill(Color.accentPrimary).frame(width: 8, height: 8)
                                        .accessibilityLabel("Unread")
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.forward").foregroundStyle(Color.textSecondary)
                            }
                            Text(verbatim: note.text)
                                .font(.body)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .environment(\.layoutDirection,
                                             CoachFeedbackText.isRightToLeft(note.text) ? .rightToLeft : .leftToRight)
                        }
                        .padding(12)
                        .frame(minHeight: 44)
                        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(note.isRunNote ? "Opens the run" : "Opens the week in your plan")
                    if unavailableNoteID == note.id {
                        Text("This run isn't on this phone.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
    }

    private func open(_ note: AthleteFeedbackNote) {
        unavailableNoteID = nil
        guard note.isRunNote else {
            router.planFocusDate = note.weekStartDate(calendar: .current)
            router.activeSheet = nil
            router.selectedTab = .plan
            return
        }
        openTask?.cancel()
        openTask = Task {
            guard let run = await AthleteFeedbackOpening.resolveRun(note, services: services) else {
                if !Task.isCancelled { unavailableNoteID = note.id }
                return
            }
            let report = await services.runReport(for: run) ?? SupabaseRunSmartServices.reportSkeleton(for: run)
            guard !Task.isCancelled else { return }
            router.open(.runReportDetail(report, run: run))
        }
    }

    private func coach(_ link: CoachLink) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Text(LeaveCoachCopy.monogram(for: link.coachName))
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.surfaceElevated, in: Circle())
                    .accessibilityLabel("\(link.coachName) avatar")
                Text(link.coachName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What \(link.coachName) can see")
                    .font(.headline)
                ForEach(CoachConsentCopy.sharedBullets(), id: \.self) { bullet in
                    Text("• \(bullet)")
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let userID = session.currentUserID, coachLinks.activeLink(for: userID)?.id == link.id {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Share route maps with \(link.coachName)", isOn: Binding(
                        get: { routes.sharing(ownerID: userID, linkID: link.id) },
                        set: { routes.setSharing($0, ownerID: userID, linkID: link.id) }
                    ))
                    Text(RouteUploadPolicy.isEnabled
                         ? "Maps already shared stay visible to \(link.coachName) until you leave."
                         : "Route uploads are currently off.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            feedbackList(link)

            Button("Leave coach") {
                model.cancel()
                showLeaveSheet = true
            }
            .buttonStyle(NeonButtonStyle(isDestructive: true))
            .disabled(model.leaveDisabledReason != nil)
            .accessibilityLabel("Leave coach")

            if let reason = model.leaveDisabledReason {
                Text(reason)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Flag off makes no v2 call (flag-off AC). A failed read keeps the 1.2.6 sheet.
    private func loadLeaveV2Lines() async {
        guard RunSmartFeatures.coachV2Enabled, let link = coachLinks.currentLink else {
            leaveIncludesV2Lines = false
            return
        }
        let status = try? await SupabaseCoachConsentRepository().status()
        guard coachLinks.currentLink?.id == link.id else { return }
        leaveIncludesV2Lines = status?.linkID == link.id && status?.linkIsV2 == true
    }

    private func startReachability() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in
                model.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "leave-coach-path"))
        pathMonitor = monitor
    }

    private func stopReachability() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }
}

/// A13. Equal-weight buttons, no timer, no second confirmation. P9's "Leave {Coach}"
/// (C7.8) opens this same sheet, with `onCancel` returning to P9.
struct LeaveCoachSheet: View {
    var coachName: String
    @ObservedObject var model: LeaveCoachModel
    var includesV2Lines = false
    var onCancel: (() -> Void)? = nil
    var onConfirm: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            content
                .padding(20)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.isWorking)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LeaveCoachCopy.sheet(coach: coachName, includesV2Lines: includesV2Lines))
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = model.isOnline ? model.errorMessage : LeaveCoachCopy.offline {
                Text(errorMessage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentAmber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    model.cancel()
                    if let onCancel { onCancel() } else { dismiss() }
                }
                .buttonStyle(.bordered)
                .disabled(model.isWorking)
                .frame(maxWidth: .infinity)

                Button {
                    Task { await onConfirm() }
                } label: {
                    if model.isWorking {
                        ProgressView()
                    } else {
                        Text("Leave \(coachName)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(maxWidth: .infinity)
                .disabled(!model.isOnline || model.isWorking)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: C7.11, the one-time removal line on Today

extension View {
    /// C7.11 AC5: after a coach removed this athlete, Today shows one neutral line, once.
    /// Renders nothing and calls nothing with v2 off, while linked, or before the link read.
    func coachLinkNotice() -> some View {
        modifier(CoachLinkNoticeHost())
    }
}

private struct CoachLinkNoticeHost: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: SupabaseSession
    @EnvironmentObject private var coachLinks: CoachLinkStore
    @EnvironmentObject private var coachV2Gate: CoachV2Gate
    @StateObject private var model = CoachLinkNoticeModel()

    private struct Inputs: Equatable {
        let v2Enabled: Bool
        let userID: UUID?
        let noLink: Bool
    }

    private var inputs: Inputs {
        let userID = session.isAuthenticated ? session.currentUserID : nil
        return Inputs(v2Enabled: coachV2Gate.isEnabled, userID: userID,
                      noLink: userID != nil && coachLinks.showsJoinCoach)
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let notice = model.notice {
                    CoachLinkNoticeCard(notice: notice) { model.dismiss() }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .task(id: notice.linkID) { await model.shown() }
                }
            }
            .task(id: inputs) { await evaluate() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await evaluate() } }
            }
    }

    private func evaluate() async {
        let current = inputs
        await model.evaluate(v2Enabled: current.v2Enabled, userID: current.userID, noLink: current.noLink)
    }
}

/// Neutral and calm: no warning color, no action besides OK (UX spec G16).
struct CoachLinkNoticeCard: View {
    let notice: CoachLinkNotice
    var onOK: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: CoachRemovalCopy.notice(coach: notice.coachName))
                .font(.bodyMD)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(CoachRemovalCopy.noticeOK, action: onOK)
                .font(.bodyMD.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
