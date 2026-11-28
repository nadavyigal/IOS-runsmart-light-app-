import SwiftUI

// C8.5: what the athlete sees when a coach lock blocks a change (spec §C.5 P3–P5).

/// P3 lock glyph with "Set by {Coach}".
struct CoachLockTag: View {
    var coachName: String

    var body: some View {
        Label(CoachLockCopy.setBy(coach: coachName), systemImage: "lock.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            .accessibilityIdentifier("coachLock.tag")
    }
}

/// Shown instead of the amend and reschedule editors when the row is coach-set (AC 5 / AC 6),
/// whichever button led there.
struct CoachLockedWorkoutNotice: View {
    var workout: WorkoutSummary
    var coachName: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CoachLockTag(coachName: coachName)
                Text(workout.title)
                    .font(.title3.bold())
                Text(CoachLockCopy.workoutLocked(coach: coachName))
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier("coachLock.workoutLocked")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// P5 Phase 2 block (AC 7): a coach-published plan can't be changed or rebuilt here.
struct CoachPlanLockedBlock: View {
    var coachName: String
    /// Only when the coach has written a note (opens the reply thread in My coach).
    var onReply: (() -> Void)?
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RunSmartSpacing.md) {
            Text(CoachLockCopy.planLockedTitle(coach: coachName))
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(CoachLockCopy.planLockedBody(coach: coachName))
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let onReply {
                Button(CoachLockCopy.replyToLatestNote(coach: coachName), action: onReply)
                    .buttonStyle(NeonButtonStyle())
                    .accessibilityIdentifier("coachLock.planReply")
            }
            Button(CoachLockCopy.ok, action: onDismiss)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityIdentifier("coachLock.planOK")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceCard.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("coachLock.planBlock")
    }
}

/// Listens for `runSmartCoachLockNotice` and shows the copy: an alert for a locked workout
/// or a taken day, the P5 block for a coach-published plan. Never a raw server error.
struct CoachLockNoticeModifier: ViewModifier {
    @ObservedObject var links: CoachLinkStore
    @ObservedObject var feedback: AthleteFeedbackStore
    /// False while another presenter owns the screen (the root while a sheet is up).
    var isActive: () -> Bool
    var openReply: () -> Void

    @State private var alertText: String?
    @State private var showsPlanBlock = false

    private var coachName: String { CoachLockCopy.coachName(links.currentLink) }

    /// "Reply to {Coach}'s latest note" shows only when that coach has written one.
    private var hasLatestNote: Bool {
        guard let coachID = links.currentLink?.coachID else { return false }
        return feedback.notes.contains { $0.coachID == coachID }
    }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .runSmartCoachLockNotice)) { note in
                guard isActive(), let notice = note.object as? CoachLockNotice else { return }
                switch notice {
                case .workoutLocked: alertText = CoachLockCopy.workoutLocked(coach: coachName)
                case .dateTaken: alertText = CoachLockCopy.dateTaken
                case .planLocked: showsPlanBlock = true
                }
            }
            .alert(
                alertText ?? "",
                isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })
            ) {
                Button(CoachLockCopy.ok, role: .cancel) { alertText = nil }
            }
            .sheet(isPresented: $showsPlanBlock) {
                CoachPlanLockedBlock(
                    coachName: coachName,
                    onReply: hasLatestNote ? {
                        showsPlanBlock = false
                        openReply()
                    } : nil,
                    onDismiss: { showsPlanBlock = false }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
    }
}

extension View {
    func coachLockNotices(
        links: CoachLinkStore,
        feedback: AthleteFeedbackStore,
        isActive: @escaping () -> Bool = { true },
        openReply: @escaping () -> Void
    ) -> some View {
        modifier(CoachLockNoticeModifier(links: links, feedback: feedback, isActive: isActive, openReply: openReply))
    }
}
