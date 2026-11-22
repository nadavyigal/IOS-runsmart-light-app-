import SwiftUI

// Story 3.3. Coach identity on Today (A5) and the Plan (A6). Every view here renders
// only from a `TodayCoachLayer` or `PlanCoachHeader`, which exist only while
// `CoachPresence` is active.

/// The monogram avatar. Always paired with the coach's name as text, so VoiceOver skips it.
struct CoachMonogram: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        Text(LeaveCoachCopy.monogram(for: name))
            .font(.labelLG)
            .foregroundStyle(Color.accentPrimary)
            .frame(width: size, height: size)
            .background(Color.surfaceElevated, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Avatar at the leading edge, then the text. At accessibility sizes the avatar stacks above.
struct CoachAvatarRow<Content: View>: View {
    let coachName: String
    var spacing: CGFloat = 10
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: spacing))
        layout {
            CoachMonogram(name: coachName)
            content
        }
    }
}

/// "Coached by {Coach}" under the Today title. Claims only whose athlete this is.
struct CoachedByStrip: View {
    let coachName: String

    var body: some View {
        CoachAvatarRow(coachName: coachName) {
            Text(verbatim: CoachPresenceCopy.coachedBy(coachName))
                .font(.bodyMD.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coached-by-strip")
    }
}

/// A5: the strip, then up to two unread notes, the "N more" row, and the loading or error row.
struct TodayCoachSection: View {
    let layer: TodayCoachLayer
    let onRead: (AthleteFeedbackNote) -> Void
    let onMore: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CoachedByStrip(coachName: layer.coachName)
            ForEach(layer.cards) { card in
                TodayCoachCardView(card: card, coachName: layer.coachName) { onRead(card.note) }
            }
            if layer.moreCount > 0 {
                Button(action: onMore) {
                    HStack {
                        Text(verbatim: CoachPresenceCopy.more(layer.moreCount, coach: layer.coachName))
                            .font(.bodyMD.weight(.semibold))
                            .foregroundStyle(Color.accentPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(Color.accentPrimary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.surfaceElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens My coach")
                .accessibilityIdentifier("coach-more-row")
            }
            switch layer.status {
            case .loading:
                AthleteFeedbackSkeleton()
            case .failed:
                CoachRefreshErrorRow(coachName: layer.coachName, retry: onRetry)
            case .ready:
                EmptyView()
            }
        }
    }
}

/// A coach note on Today. It stays until the athlete reads it: no dismiss, no reply.
struct TodayCoachCardView: View {
    let card: TodayCoachCard
    let coachName: String
    let onRead: () -> Void

    var body: some View {
        CoachSignedCard(title: card.title, text: card.note.text, coachName: coachName) {
            Button(action: onRead) {
                Text(CoachPresenceCopy.read)
                    .font(.bodyMD.weight(.semibold))
                    .frame(minWidth: 88, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentPrimary)
            .accessibilityHint(readHint)
        }
        .accessibilityIdentifier("today-coach-card")
    }

    private var readHint: String {
        switch CoachNoteDestination.of(card.note) {
        case .welcome: "Marks the welcome as read"
        case .run: "Opens the run"
        case .week: "Opens the week in your plan"
        }
    }
}

struct CoachSignedCard<Footer: View>: View {
    let title: String
    let text: String
    let coachName: String
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachAvatarRow(coachName: coachName, spacing: 8) {
                Text(verbatim: title)
                    .font(.labelLG)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            CoachFeedbackBody(text: text)
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accentPrimary.opacity(0.35), lineWidth: 1))
    }
}

struct CoachRefreshErrorRow: View {
    let coachName: String
    let retry: () -> Void

    var body: some View {
        HStack {
            Text(verbatim: CoachPresenceCopy.refreshFailed(coachName))
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(CoachPresenceCopy.retry, action: retry)
                .foregroundStyle(Color.accentPrimary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 14)
        .background(Color.surfaceElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("coach-refresh-error")
    }
}

/// A6: "Coached by {Coach}", then the coach's plan title and sub-line. Opens My coach.
/// While the Plan Mode is unknown it shows the strip over the solo title.
struct PlanCoachHeaderView: View {
    let header: PlanCoachHeader
    let soloTitle: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                CoachAvatarRow(coachName: header.coachName) {
                    Text(verbatim: CoachPresenceCopy.coachedBy(header.coachName))
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(verbatim: header.titleText ?? soloTitle)
                    .font(.displayMD)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let subline = header.sublineText {
                    Text(verbatim: subline)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens My coach")
        .accessibilityIdentifier("plan-coach-header")
    }
}

/// Opens a coach note's run (run detail) or week (Plan). Shared by Today and My coach.
enum AthleteFeedbackOpening {
    /// Looks the run up in every stored run first (no recent-runs limit), then in recent runs.
    static func resolveRun(_ note: AthleteFeedbackNote, services: any RunSmartServiceProviding) async -> RecordedRun? {
        if let id = note.runSourceActivityID,
           let stored = await services.recordedRun(forReportRunID: id),
           note.matches(stored) {
            // May be the merged run for this activity (for example its Apple Health copy);
            // it carries the note's key in `mergedSourceKeys`, so the report shows the note.
            return stored
        }
        return await services.recentRuns().first { note.matches($0) }
    }
}

// MARK: C7.8 P9, the one-time sharing notice

extension View {
    /// C7.8 P9 on Today: shown once to an athlete who joined before v2, while v2 is on and
    /// the link is v2. Renders nothing and calls nothing with v2 off.
    func coachConsentNotice() -> some View {
        modifier(CoachConsentNoticeHost())
    }
}

private struct CoachConsentNoticeHost: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: SupabaseSession
    @EnvironmentObject private var coachLinks: CoachLinkStore
    @EnvironmentObject private var coachV2Gate: CoachV2Gate
    @StateObject private var model = CoachConsentNoticeModel()
    @StateObject private var leaveModel = LeaveCoachModel()

    private struct Inputs: Equatable {
        let v2Enabled: Bool
        let userID: UUID?
        let linkID: UUID?
    }

    private var inputs: Inputs {
        let userID = session.isAuthenticated ? session.currentUserID : nil
        return Inputs(
            v2Enabled: coachV2Gate.isEnabled,
            userID: userID,
            linkID: coachLinks.activeLink(for: userID)?.id
        )
    }

    func body(content: Content) -> some View {
        content
            .task(id: inputs) { await evaluate() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                model.beginForeground()
                Task { await evaluate() }
            }
            .sheet(item: noticeBinding) { notice in
                CoachConsentNoticeSheet(
                    notice: notice,
                    model: model,
                    leaveModel: leaveModel,
                    onLeave: { await confirmLeave(notice) }
                )
            }
    }

    private func evaluate() async {
        let current = inputs
        await model.evaluate(v2Enabled: current.v2Enabled, userID: current.userID, linkID: current.linkID)
    }

    /// A swipe-away hides P9 until the next foreground (C7.8 AC4).
    private var noticeBinding: Binding<CoachConsentNotice?> {
        Binding(
            get: { model.notice },
            set: { value in if value == nil { model.dismissForNow() } }
        )
    }

    private func confirmLeave(_ notice: CoachConsentNotice) async {
        guard let userID = session.currentUserID else { return }
        let toast = await leaveModel.confirm(
            coachName: notice.coachName,
            userID: userID,
            store: coachLinks,
            expectedLinkID: notice.linkID
        )
        guard toast != nil else { return }
        await evaluate()
    }
}

/// P9. OK and "Leave {Coach}" are the same size with no pressure styling (MVP leave rules).
/// "Leave {Coach}" opens the existing A13 leave sheet in place, never an instant leave.
private struct CoachConsentNoticeSheet: View {
    let notice: CoachConsentNotice
    @ObservedObject var model: CoachConsentNoticeModel
    @ObservedObject var leaveModel: LeaveCoachModel
    let onLeave: () async -> Void
    @State private var showsLeave = false

    var body: some View {
        if showsLeave {
            LeaveCoachSheet(
                coachName: notice.coachName,
                model: leaveModel,
                includesV2Lines: true,
                onCancel: { showsLeave = false },
                onConfirm: onLeave
            )
        } else {
            ScrollView {
                noticeContent
                    .padding(20)
            }
            .presentationDetents([.large])
            .interactiveDismissDisabled(model.isWorking)
        }
    }

    private var noticeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: CoachConsentCopy.noticeTitle(coach: notice.coachName))
                .font(.displayMD)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: CoachConsentCopy.noticeBody(coach: notice.coachName))
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                noticeButton(CoachConsentCopy.noticeOK) {
                    Task { await model.acknowledge() }
                }
                noticeButton(CoachConsentCopy.noticeLeave(coach: notice.coachName)) {
                    model.leaveTapped()
                    leaveModel.cancel()
                    showsLeave = true
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("coach-consent-notice")
    }

    private func noticeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if model.isWorking, title == CoachConsentCopy.noticeOK {
                    ProgressView()
                } else {
                    Text(verbatim: title)
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.textPrimary)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))
        .disabled(model.isWorking)
        .accessibilityLabel(title)
    }
}
