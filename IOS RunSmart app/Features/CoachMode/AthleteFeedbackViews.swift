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

/// A coach's note, pinned and always expanded. With Coach v2 on, the athlete's replies show under it,
/// and Reply shows while `replyLink` is the current link to the note's coach (C7.7). Off: read-only.
struct AthleteFeedbackCard: View {
    let note: AthleteFeedbackNote
    var replyLink: CoachLink? = nil
    var replyService: AthleteFeedbackReplyService = .shared

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
            FeedbackReplyThread(note: note, link: replyLink, service: replyService)
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
                ForEach(notes) { AthleteFeedbackCard(note: $0, replyLink: link) }
            }
            .task(id: notes.map(\.id)) {
                if marksRead { await feedback.markRead(notes) }
            }
        } else if feedback.loadState == .loading, run.endedAt > (link?.consentedAt ?? .distantFuture) {
            AthleteFeedbackSkeleton()
        } else if feedback.loadState == .failed, let link, run.endedAt > link.consentedAt {
            AthleteFeedbackError(coachName: link.coachName) { Task { await feedback.load() } }
        } else if let link, feedback.reviewLine(for: run, link: link) != nil {
            // Redraws once at the 72-hour mark, so a screen left open switches lines. No countdown.
            TimelineView(.explicit([run.endedAt.addingTimeInterval(AthleteFeedbackRPC.reviewWindow)])) { context in
                if let line = feedback.reviewLine(for: run, link: link, now: max(context.date, .now)) {
                    CoachReviewLineView(line: line, coachName: link.coachName)
                }
            }
        }
    }
}

/// Plan week view: week notes pinned at the top of their week. Opening it marks them read.
struct AthleteWeekFeedbackSection: View {
    let start: Date
    let end: Date
    var calendar: Calendar = .current
    @EnvironmentObject private var feedback: AthleteFeedbackStore
    @EnvironmentObject private var coachLinks: CoachLinkStore

    var body: some View {
        let notes = feedback.notes(weekFrom: start, to: end, calendar: calendar)
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(notes) { AthleteFeedbackCard(note: $0, replyLink: coachLinks.currentLink) }
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

// MARK: - C7.7 P6 reply

/// The athlete's replies under one coach note, Reply, and the inline composer (UX spec C.5 P6).
/// Renders nothing while Coach v2 is off. After the link ends the replies stay and Reply hides (AC6).
struct FeedbackReplyThread: View {
    let note: AthleteFeedbackNote
    let link: CoachLink?
    @ObservedObject var service: AthleteFeedbackReplyService
    @State private var composing: Bool
    @State private var text: String
    @State private var sending = false
    @FocusState private var focused: Bool

    /// `draft` opens the composer with that text (fixtures and previews).
    init(note: AthleteFeedbackNote, link: CoachLink?, service: AthleteFeedbackReplyService = .shared,
         draft: String? = nil) {
        self.note = note
        self.link = link
        self.service = service
        _composing = State(initialValue: draft != nil)
        _text = State(initialValue: draft ?? "")
    }

    var body: some View {
        if service.isVisible {
            let replies = service.replies(for: note)
            let canReply = service.canReply(note: note, link: link)
            let notice = service.linkGoneNotice?.feedbackID == note.id ? service.linkGoneNotice?.coachName : nil
            if !replies.isEmpty || canReply || notice != nil {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(replies) { FeedbackReplyRow(reply: $0) }
                    if let notice {
                        Text(FeedbackReplyCopy.notSent(coach: notice))
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .onDisappear { service.linkGoneNotice = nil }
                    }
                    if canReply {
                        if composing {
                            composer(coach: link?.coachName ?? note.coachName)
                        } else {
                            Button {
                                composing = true
                                focused = true
                            } label: {
                                Label(FeedbackReplyCopy.reply, systemImage: "arrowshape.turn.up.left")
                                    .font(.labelLG)
                                    .foregroundStyle(Color.accentPrimary)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("feedback-reply-button")
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func composer(coach: String) -> some View {
        let tooLong = FeedbackReplyPolicy.isTooLong(text)
        VStack(alignment: .leading, spacing: 6) {
            TextField(FeedbackReplyCopy.placeholder(coach: coach), text: $text, axis: .vertical)
                .font(.bodyMD)
                .lineLimit(2...8)
                .focused($focused)
                .naturalTextDirection(text)
                .padding(10)
                .background(Color.surfaceBase.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(FeedbackReplyCopy.composerLabel(coach: coach))
                .accessibilityIdentifier("feedback-reply-field")
                .onChange(of: FeedbackReplyPolicy.length(text)) { old, new in announceThresholds(old: old, new: new) }
            HStack(spacing: 8) {
                if tooLong {
                    Text(FeedbackReplyCopy.tooLong)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentHeart)
                        .accessibilityIdentifier("feedback-reply-too-long")
                } else if FeedbackReplyPolicy.showsCounter(text) {
                    Text(verbatim: FeedbackReplyCopy.counter(FeedbackReplyPolicy.length(text)))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
                Button(FeedbackReplyCopy.send) {
                    guard !sending else { return }
                    sending = true
                    let draft = text
                    Task {
                        if await service.send(draft, note: note, link: link) {
                            text = ""
                            composing = false
                        }
                        sending = false
                    }
                }
                .buttonStyle(NeonButtonStyle())
                .disabled(!FeedbackReplyPolicy.canSend(text) || sending)
                .accessibilityIdentifier("feedback-reply-send")
            }
        }
    }

    /// The count is announced at 900 and at 1000 (UX spec C.8).
    private func announceThresholds(old: Int, new: Int) {
        for mark in [FeedbackReplyCopy.counterFrom, FeedbackReplyCopy.limit] where old < mark && new >= mark {
            AccessibilityNotification.Announcement(FeedbackReplyCopy.counter(new)).post()
        }
        if old <= FeedbackReplyCopy.limit && new > FeedbackReplyCopy.limit {
            AccessibilityNotification.Announcement(FeedbackReplyCopy.tooLong).post()
        }
    }
}

/// "You · 14:32" with "Sent", "Waiting to send" or "Couldn't send. We'll try again.", then the text.
struct FeedbackReplyRow: View {
    let reply: AthleteFeedbackReply

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(verbatim: FeedbackReplyCopy.you(FeedbackReplyFormat.time(reply.createdAt)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                switch reply.status {
                case .sent:
                    Text(FeedbackReplyCopy.sent).font(.caption).foregroundStyle(Color.textSecondary)
                case .waiting:
                    Label(FeedbackReplyCopy.waiting, systemImage: "clock")
                        .font(.caption).foregroundStyle(Color.textTertiary)
                case .retrying:
                    Text(FeedbackReplyCopy.couldNotSend).font(.caption).foregroundStyle(Color.textTertiary)
                }
                Spacer(minLength: 0)
            }
            Text(verbatim: reply.text)
                .font(.bodyMD)
                .foregroundStyle(Color.textPrimary)
                .naturalTextDirection(reply.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceBase.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feedback-reply-row")
    }
}
