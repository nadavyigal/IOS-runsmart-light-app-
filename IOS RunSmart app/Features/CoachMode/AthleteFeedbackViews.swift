import SwiftUI

/// "{Coach} · 12 Nov" and the VoiceOver sentence "Feedback from {Coach}, 12 November".
enum AthleteFeedbackFormat {
    static func shortDate(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        format(date, template: "dMMM", locale: locale, timeZone: timeZone)
    }

    static func longDate(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        format(date, template: "dMMMM", locale: locale, timeZone: timeZone)
    }

    static func header(_ note: AthleteFeedbackNote, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        "\(note.coachName) · \(CoachMetricFormat.isolate(shortDate(note.createdAt, locale: locale, timeZone: timeZone)))"
    }

    static func spoken(_ note: AthleteFeedbackNote, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        "Feedback from \(note.coachName), \(longDate(note.createdAt, locale: locale, timeZone: timeZone))"
            + (note.editedAt == nil ? "" : ", edited")
    }

    private static func format(_ date: Date, template: String, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

/// A coach's note, pinned and always expanded. Read-only: no reply or actions.
struct AthleteFeedbackCard: View {
    let note: AthleteFeedbackNote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(LeaveCoachCopy.monogram(for: note.coachName))
                    .font(.labelLG)
                    .foregroundStyle(Color.accentPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.surfaceElevated, in: Circle())
                    .accessibilityHidden(true)
                Text(verbatim: AthleteFeedbackFormat.header(note))
                    .font(.labelLG)
                    .foregroundStyle(Color.textSecondary)
                if note.editedAt != nil {
                    Text(AthleteFeedbackCopy.edited)
                        .font(.labelLG)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AthleteFeedbackFormat.spoken(note))
            .accessibilityAddTraits(.isHeader)
            CoachFeedbackBody(text: note.text)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accentPrimary.opacity(0.35), lineWidth: 1))
        .accessibilityIdentifier("athlete-feedback-note")
    }
}

/// "{Coach} will review this run" or "Shared with {Coach}". No spinner, no countdown.
struct CoachReviewLineView: View {
    let line: CoachReviewLine
    let coachName: String

    var body: some View {
        HStack(spacing: 8) {
            Text(LeaveCoachCopy.monogram(for: coachName))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 28, height: 28)
                .background(Color.surfaceElevated, in: Circle())
                .accessibilityHidden(true)
            Text(line.text)
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach-review-line")
    }
}

/// Run detail (A10) and the post-run summary (A9): the coach's notes on this run, or the
/// pending line while linked. Opening it records `read_at`.
struct AthleteRunFeedbackSection: View {
    let run: RecordedRun?
    var marksRead = true
    @EnvironmentObject private var feedback: AthleteFeedbackStore
    @EnvironmentObject private var coachLinks: CoachLinkStore

    var body: some View {
        if let run {
            content(run)
        }
    }

    @ViewBuilder
    private func content(_ run: RecordedRun) -> some View {
        let notes = feedback.notes(for: run)
        let link = coachLinks.currentLink
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(notes) { AthleteFeedbackCard(note: $0) }
            }
            .task(id: notes.map(\.id)) {
                if marksRead { await feedback.markRead(notes) }
            }
        } else if feedback.loadState == .loading, run.endedAt > (link?.consentedAt ?? .distantFuture) {
            AthleteFeedbackSkeleton()
        } else if feedback.loadState == .failed, let link, run.endedAt > link.consentedAt {
            AthleteFeedbackError(coachName: link.coachName) { Task { await feedback.load() } }
        } else if let link, let line = feedback.reviewLine(for: run, link: link) {
            CoachReviewLineView(line: line, coachName: link.coachName)
        }
    }
}

/// Plan week view: week notes pinned at the top of their week. Opening it marks them read.
struct AthleteWeekFeedbackSection: View {
    let start: Date
    let end: Date
    var calendar: Calendar = .current
    @EnvironmentObject private var feedback: AthleteFeedbackStore

    var body: some View {
        let notes = feedback.notes(weekFrom: start, to: end, calendar: calendar)
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(notes) { AthleteFeedbackCard(note: $0) }
            }
            .task(id: notes.map(\.id)) { await feedback.markRead(notes) }
        }
    }
}

struct AthleteFeedbackSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule().frame(width: 140, height: 10)
            Capsule().frame(maxWidth: .infinity).frame(height: 10)
            Capsule().frame(width: 200, height: 10)
        }
        .foregroundStyle(Color.textSecondary.opacity(0.2))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your coach's note")
    }
}

struct AthleteFeedbackError: View {
    let coachName: String
    let retry: () -> Void

    var body: some View {
        HStack {
            Text(AthleteFeedbackCopy.loadFailed(coachName))
                .font(.bodyMD)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Button("Retry", action: retry)
                .foregroundStyle(Color.accentPrimary)
                .frame(minHeight: 44)
        }
        .padding(14)
        .background(Color.surfaceElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
