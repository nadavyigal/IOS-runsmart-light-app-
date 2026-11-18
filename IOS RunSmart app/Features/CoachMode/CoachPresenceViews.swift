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
        VStack(alignment: .leading, spacing: 10) {
            CoachAvatarRow(coachName: coachName, spacing: 8) {
                Text(verbatim: card.title)
                    .font(.labelLG)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            // Never truncated; each paragraph keeps its own direction (Hebrew allowed).
            CoachFeedbackBody(text: card.note.text)
            Button(action: onRead) {
                Text(CoachPresenceCopy.read)
                    .font(.bodyMD.weight(.semibold))
                    .frame(minWidth: 88, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentPrimary)
            .accessibilityHint(card.note.isRunNote ? "Opens the run" : "Opens the week in your plan")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accentPrimary.opacity(0.35), lineWidth: 1))
        .accessibilityIdentifier("today-coach-card")
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
