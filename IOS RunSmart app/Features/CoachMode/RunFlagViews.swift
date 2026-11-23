import SwiftUI

// C7.4 views. "Coach" means a HUMAN coach (Coach Mode). Copy: UX spec C.5 P7 (athlete) and A.6 T4 (coach).

/// P7 "Something off?" on the run summary, or with `run == nil` the run-less entry for Today.
/// Renders nothing unless C7.3's sharing context is sharing (C7.4 AC9): no ack, not v2, solo or flag
/// off hides it, so "{Coach} will see this" never shows when it is not true.
struct AthleteRunFlagSection: View {
    let run: RecordedRun?
    @ObservedObject var service: AthleteRunFlagService = .shared

    @State private var expanded = false
    @State private var kind: RunFlagKind?
    @State private var note = ""
    @State private var sending = false

    var body: some View {
        if let coach = service.coachName {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(service.flags(for: run)) { flag in
                    sentFlag(flag, coach: coach)
                }
                if service.linkGoneNotice {
                    Text(RunFlagCopy.notSent(coach: coach))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .onDisappear { service.linkGoneNotice = false }
                }
                entry(coach: coach)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func entry(coach: String) -> some View {
        RunSmartPanel(cornerRadius: 18, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack {
                        Label(RunFlagCopy.entry, systemImage: "exclamationmark.bubble")
                            .font(.bodyMD.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: expanded ? "chevron.down" : "chevron.forward")
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("flag-entry")

                if expanded {
                    form(coach: coach)
                }
            }
        }
    }

    @ViewBuilder
    private func form(coach: String) -> some View {
        // Pain and Something else are a radio group (UX spec C.8).
        HStack(spacing: 8) {
            ForEach(RunFlagKind.allCases, id: \.self) { option in
                Button {
                    kind = option
                } label: {
                    Text(option.athleteLabel)
                        .font(.labelLG)
                        .foregroundStyle(kind == option ? Color.surfaceBase : Color.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(kind == option ? Color.accentPrimary : Color.surfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(kind == option ? [.isSelected] : [])
            }
        }
        TextField(RunFlagCopy.notePlaceholder, text: $note, axis: .vertical)
            .font(.bodyMD)
            .lineLimit(2...5)
            .naturalTextDirection(note)
            .onChange(of: note) { _, value in
                if value.count > RunFlagCopy.noteLimit { note = String(value.prefix(RunFlagCopy.noteLimit)) }
            }
        Text(RunFlagCopy.willSee(coach: coach) + " " + RunFlagCopy.safety)
            .font(.caption)
            .foregroundStyle(Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        Button(RunFlagCopy.send(coach: coach)) {
            guard let kind, !sending else { return }
            sending = true
            Task {
                await service.send(kind: kind, note: note, run: run)
                self.kind = nil
                note = ""
                expanded = false
                sending = false
            }
        }
        .buttonStyle(NeonButtonStyle())
        .disabled(kind == nil || sending)
    }

    private func sentFlag(_ flag: AthleteRunFlag, coach: String) -> some View {
        RunSmartPanel(cornerRadius: 18, padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label(flag.kind.athleteLabel, systemImage: flag.kind == .pain ? "bandage" : "exclamationmark.bubble")
                    .font(.labelLG)
                    .foregroundStyle(Color.textPrimary)
                if let text = flag.note {
                    Text(verbatim: text)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .naturalTextDirection(text)
                }
                switch flag.status {
                case .waiting:
                    Label(RunFlagCopy.waiting, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                case .sent:
                    Text(RunFlagCopy.sent(coach: coach))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                case .seen:
                    Text(RunFlagCopy.saw(coach: coach))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                }
                // The safety line after sending (MVP voice rule 7). Never a response-time promise.
                Text(RunFlagCopy.safety)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if flag.canRemove {
                    Button(RunFlagCopy.removeFlag) {
                        Task { await service.remove(flag) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentPrimary)
                    .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// T4: one flag inside the coach's athlete or day detail (UX spec A.6). Lane B places it in
/// `CoachAthleteDetail.swift`; this view only needs the flag and two actions.
struct CoachFlagBlock: View {
    let flag: CoachRunFlag
    let athleteName: String
    var calendar: Calendar = .current
    var waiting = false
    let markHandled: () -> Void
    var writeTo: (() -> Void)?

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(RunFlagCopy.title(flag.kind, date: flag.createdAt, calendar: calendar),
                      systemImage: flag.kind == .pain ? "bandage" : "exclamationmark.bubble")
                    .font(.headingMD)
                    .foregroundStyle(Color.accentHeart)
                    .accessibilityAddTraits(.isHeader)
                if flag.runDeleted {
                    Text(RunFlagCopy.runDeleted).font(.bodyMD).foregroundStyle(Color.textSecondary)
                }
                if let note = flag.note {
                    // Verbatim, in the athlete's own direction.
                    Text(verbatim: note)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textPrimary)
                        .naturalTextDirection(note)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let resolved = flag.resolvedAt {
                    // One coach per athlete, so a resolved flag was handled by this coach.
                    Text(RunFlagCopy.handledByYou(resolved, calendar: calendar))
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                } else if waiting {
                    Label("Waiting to sync", systemImage: "clock")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    Button(RunFlagCopy.markHandled, action: markHandled)
                        .buttonStyle(NeonButtonStyle())
                }
                if let writeTo {
                    Button(RunFlagCopy.writeTo(athlete: athleteName), action: writeTo)
                        .font(.labelLG)
                        .foregroundStyle(Color.accentPrimary)
                        .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
