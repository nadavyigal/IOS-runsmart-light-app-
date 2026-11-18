import Combine
import Network
import SwiftUI
import UIKit

// MARK: - Store

/// The coach's notes for one athlete, shared by the athlete detail (C5) and day detail (C6).
@MainActor
final class CoachFeedbackStore: ObservableObject {
    @Published private(set) var notes: [CoachFeedback] = []
    @Published private(set) var revoked = false
    let athleteID: UUID
    let athleteName: String
    let service: any CoachFeedbackServing
    let outbox: CoachFeedbackOutbox
    private var monitor: NWPathMonitor?

    init(athleteID: UUID, athleteName: String,
         service: any CoachFeedbackServing = SupabaseCoachFeedbackService(),
         outbox: CoachFeedbackOutbox = .shared) {
        self.athleteID = athleteID
        self.athleteName = athleteName
        self.service = service
        self.outbox = outbox
    }

    func notes(for target: CoachFeedbackTarget) -> [CoachFeedback] {
        notes.filter { $0.target == target }
    }

    /// Sends anything queued first, then reads the coach's notes for this athlete.
    func load() async {
        await flush()
        if let rows = try? await service.list(athleteID: athleteID) {
            notes = rows.sorted { $0.createdAt < $1.createdAt }
        }
    }

    func upsert(_ note: CoachFeedback) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.append(note)
        }
    }

    func markRevoked() { revoked = true }

    func flush() async {
        for note in await outbox.flush(using: service) where note.athleteID == athleteID {
            upsert(note)
        }
    }

    /// Retries the queue when the connection comes back.
    func startReachability() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.flush() }
        }
        monitor.start(queue: DispatchQueue(label: "coach-feedback-path"))
        self.monitor = monitor
    }

    func stopReachability() {
        monitor?.cancel()
        monitor = nil
    }
}

// MARK: - Composer model

/// What opens the composer: a run, a week, or one of the coach's own notes to edit.
struct CoachFeedbackRequest: Identifiable, Equatable {
    let id = UUID()
    let run: CoachFeedbackTarget?
    let week: CoachFeedbackTarget
    let initial: CoachFeedbackTarget
    let editing: CoachFeedback?

    static func onRun(_ runID: Int64, weekStart: String) -> Self {
        Self(run: .run(runID), week: .week(weekStart), initial: .run(runID), editing: nil)
    }

    static func onWeek(_ weekStart: String) -> Self {
        Self(run: nil, week: .week(weekStart), initial: .week(weekStart), editing: nil)
    }

    static func edit(_ note: CoachFeedback, weekStart: String) -> Self? {
        guard let target = note.target else { return nil }
        let run: CoachFeedbackTarget? = if case .run = target { target } else { nil }
        return Self(run: run, week: .week(weekStart), initial: target, editing: note)
    }
}

enum CoachFeedbackCopy {
    static func sent(_ name: String) -> String { "Sent. \(name) will see this in the app." }
    static let notSent = "Not sent. Saved on this phone."
    static func left(_ name: String) -> String { "\(name) has left your group" }
    static let onRun = "On this run"
    static let onWeek = "On the week"
}

@MainActor
final class CoachFeedbackComposerModel: ObservableObject {
    enum Status: Equatable { case idle, sending, sent, notSent, revoked }

    @Published var target: CoachFeedbackTarget {
        didSet {
            guard oldValue != target, editing == nil else { return }
            drafts.save(text, athleteID: athleteID, target: oldValue)
            text = drafts.draft(athleteID: athleteID, target: target) ?? ""
            selection = NSRange(location: (text as NSString).length, length: 0)
            pendingIDs[oldValue] = pendingID
            pendingID = pendingIDs[target] ?? UUID()
            status = .idle
        }
    }
    @Published var text: String {
        didSet {
            guard oldValue != text else { return }
            if let editing, CoachFeedbackText.trimmed(text) == editing.text {
                drafts.clear(athleteID: athleteID, scope: draftScope)
            } else {
                drafts.save(text, athleteID: athleteID, scope: draftScope)
            }
            if status == .notSent || status == .sent { status = .idle }
        }
    }
    @Published var selection: NSRange
    @Published private(set) var status: Status = .idle

    let athleteID: UUID
    let athleteName: String
    let request: CoachFeedbackRequest
    var editing: CoachFeedback? { request.editing }
    private let service: any CoachFeedbackServing
    private let drafts: CoachFeedbackDraftStore
    private let outbox: CoachFeedbackOutbox
    /// One id per note being written, so Retry and the reconnect queue never store it twice.
    private var pendingID = UUID()
    private var pendingIDs: [CoachFeedbackTarget: UUID] = [:]
    /// Edits keep their own draft, so "Keep" restores an edit in progress too.
    private var draftScope: String { editing.map { "edit-\($0.id.uuidString)" } ?? target.key }

    init(request: CoachFeedbackRequest, athleteID: UUID, athleteName: String,
         service: any CoachFeedbackServing, drafts: CoachFeedbackDraftStore = CoachFeedbackDraftStore(),
         outbox: CoachFeedbackOutbox = .shared) {
        self.request = request
        self.athleteID = athleteID
        self.athleteName = athleteName
        self.service = service
        self.drafts = drafts
        self.outbox = outbox
        target = request.initial
        let scope = request.editing.map { "edit-\($0.id.uuidString)" } ?? request.initial.key
        let initialText = drafts.draft(athleteID: athleteID, scope: scope) ?? request.editing?.text ?? ""
        text = initialText
        selection = NSRange(location: (initialText as NSString).length, length: 0)
    }

    var canSend: Bool {
        guard status != .sending, status != .revoked, CoachFeedbackText.canSend(text) else { return false }
        if let editing { return CoachFeedbackText.trimmed(text) != editing.text }
        return true
    }

    var showsTargetPicker: Bool { editing == nil && request.run != nil }

    /// Text that would be lost if the sheet closed now.
    var hasUnsentText: Bool {
        guard status != .sent, status != .revoked else { return false }
        let value = CoachFeedbackText.trimmed(text)
        if let editing { return !value.isEmpty && value != editing.text }
        return !value.isEmpty
    }

    /// Inserts a quick chip at the cursor. Never sends.
    func insertChip(_ chip: String) {
        let result = CoachFeedbackText.insert(chip, into: text, at: selection)
        text = result.text
        selection = result.cursor
    }

    /// Sends on an explicit tap. Returns the stored note on success.
    @discardableResult
    func send() async -> CoachFeedback? {
        guard canSend else { return nil }
        let value = CoachFeedbackText.trimmed(text)
        status = .sending
        let id = editing?.id ?? pendingID
        do {
            let note: CoachFeedback
            if let editing {
                note = try await service.edit(id: editing.id, text: value)
            } else {
                note = try await service.add(id: id, athleteID: athleteID, target: target, text: value)
            }
            outbox.remove(id: id)
            drafts.clear(athleteID: athleteID, scope: draftScope)
            status = .sent
            return note
        } catch {
            switch CoachFeedbackError.map(error) {
            case .notLinked:
                outbox.remove(id: id)
                drafts.clear(athleteID: athleteID, scope: draftScope)
                status = .revoked
            case .notSent:
                outbox.enqueue(PendingCoachFeedback(
                    id: id, athleteID: athleteID, target: target, text: value,
                    kind: editing == nil ? .add : .edit
                ))
                status = .notSent
            }
            return nil
        }
    }

    /// Drops the text and any queued send of it, so a discarded note is never sent on reconnect.
    func discardDraft() {
        drafts.clear(athleteID: athleteID, scope: draftScope)
        outbox.remove(id: editing?.id ?? pendingID)
    }
}

// MARK: - Composer view (C10)

struct CoachFeedbackComposer: View {
    @StateObject private var model: CoachFeedbackComposerModel
    let onSaved: (CoachFeedback) -> Void
    let onRevoked: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var detent: PresentationDetent = .medium
    @State private var asksKeepDraft = false

    init(request: CoachFeedbackRequest, store: CoachFeedbackStore,
         onSaved: @escaping (CoachFeedback) -> Void, onRevoked: @escaping () -> Void) {
        _model = StateObject(wrappedValue: CoachFeedbackComposerModel(
            request: request, athleteID: store.athleteID, athleteName: store.athleteName,
            service: store.service, outbox: store.outbox
        ))
        self.onSaved = onSaved
        self.onRevoked = onRevoked
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.editing == nil ? "Feedback for \(model.athleteName)" : "Edit feedback")
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close") { close() }
                    .foregroundStyle(Color.accentPrimary)
            }

            if model.showsTargetPicker, let run = model.request.run {
                Picker("Feedback on", selection: $model.target) {
                    Text(CoachFeedbackCopy.onRun).tag(run)
                    Text(CoachFeedbackCopy.onWeek).tag(model.request.week)
                }
                .pickerStyle(.segmented)
            }

            CoachFeedbackTextEditor(text: $model.text, selection: $model.selection) {
                detent = .large
            }
            .frame(minHeight: 96)
            .padding(8)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: RunSmartRadius.md, style: .continuous))
            .accessibilityIdentifier("coach-feedback-text")

            chips
            statusLine

            Button {
                Task {
                    if let note = await model.send() {
                        RunSmartHaptics.success()
                        onSaved(note)
                        try? await Task.sleep(for: .seconds(1.5))
                        dismiss()
                    } else if model.status == .revoked {
                        try? await Task.sleep(for: .seconds(2))
                        onRevoked()
                        dismiss()
                    }
                }
            } label: {
                if model.status == .sending {
                    ProgressView().tint(Color.black)
                } else {
                    Text(model.editing == nil ? "Send" : "Save")
                }
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(!model.canSend)
            .accessibilityIdentifier("coach-feedback-send")
        }
        .padding(18)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(model.hasUnsentText)
        .background(SheetDismissAttemptObserver(blocked: model.hasUnsentText) { asksKeepDraft = true })
        .confirmationDialog("Keep draft?", isPresented: $asksKeepDraft, titleVisibility: .visible) {
            Button("Keep") { dismiss() }
            Button("Discard", role: .destructive) {
                model.discardDraft()
                dismiss()
            }
        }
    }

    private var chips: some View {
        Group {
            if typeSize >= .xxLarge {
                VStack(alignment: .leading, spacing: 8) { chipButtons }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { chipButtons }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick chips")
    }

    private var chipButtons: some View {
        ForEach(CoachFeedbackText.chips, id: \.self) { chip in
            Button { model.insertChip(chip) } label: {
                Text(chip)
                    .font(.bodyMD)
                    .foregroundStyle(Color.accentPrimary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Color.surfaceElevated, in: Capsule())
                    .overlay(Capsule().stroke(Color.accentPrimary.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Adds this text. Does not send.")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch model.status {
        case .sent:
            Text(CoachFeedbackCopy.sent(model.athleteName))
                .font(.bodyMD).foregroundStyle(Color.accentSuccess)
        case .notSent:
            HStack {
                Text(CoachFeedbackCopy.notSent).font(.bodyMD).foregroundStyle(Color.textPrimary)
                Spacer()
                Button("Retry") { Task { if let note = await model.send() { onSaved(note); dismiss() } } }
                    .foregroundStyle(Color.accentPrimary)
            }
        case .revoked:
            Text(CoachFeedbackCopy.left(model.athleteName))
                .font(.bodyMD).foregroundStyle(Color.textPrimary)
        case .idle, .sending:
            EmptyView()
        }
    }

    private func close() {
        if model.hasUnsentText { asksKeepDraft = true } else { dismiss() }
    }
}

/// UITextView, because SwiftUI on iOS 17 can't read the cursor (chips insert there) and
/// UITextView sets each paragraph's direction from its text, so Hebrew right-aligns.
struct CoachFeedbackTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var onFocus: () -> Void = {}

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textColor = UIColor(Color.textPrimary)
        view.textAlignment = .natural
        let style = NSMutableParagraphStyle()
        style.baseWritingDirection = .natural
        style.alignment = .natural
        view.typingAttributes[.paragraphStyle] = style
        view.accessibilityLabel = "Feedback"
        view.text = text
        view.selectedRange = selection
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
        if view.selectedRange != selection, selection.location + selection.length <= (view.text as NSString).length {
            view.selectedRange = selection
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CoachFeedbackTextEditor
        init(_ parent: CoachFeedbackTextEditor) { self.parent = parent }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocus() }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidChangeSelection(_ textView: UITextView) { parent.selection = textView.selectedRange }
    }
}

/// Tells the sheet when a swipe-down was blocked by `interactiveDismissDisabled`, so the
/// composer can ask "Keep draft?". Other delegate calls go on to SwiftUI's own delegate.
private struct SheetDismissAttemptObserver: UIViewControllerRepresentable {
    let blocked: Bool
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.onAttempt = onAttempt
        context.coordinator.blocked = blocked
        DispatchQueue.main.async {
            guard let presentation = controller.presentationController,
                  presentation.delegate !== context.coordinator else { return }
            context.coordinator.original = presentation.delegate
            presentation.delegate = context.coordinator
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onAttempt: onAttempt) }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var onAttempt: () -> Void
        /// Our own answer, so unsent text blocks a swipe even if SwiftUI's delegate is not wrapped yet.
        var blocked = false
        weak var original: UIAdaptivePresentationControllerDelegate?
        init(onAttempt: @escaping () -> Void) { self.onAttempt = onAttempt }

        func presentationControllerDidAttemptToDismiss(_ controller: UIPresentationController) {
            if blocked { onAttempt() }
            original?.presentationControllerDidAttemptToDismiss?(controller)
        }

        func presentationControllerShouldDismiss(_ controller: UIPresentationController) -> Bool {
            !blocked && (original?.presentationControllerShouldDismiss?(controller) ?? true)
        }

        func presentationControllerWillDismiss(_ controller: UIPresentationController) {
            original?.presentationControllerWillDismiss?(controller)
        }

        func presentationControllerDidDismiss(_ controller: UIPresentationController) {
            original?.presentationControllerDidDismiss?(controller)
        }
    }
}

// MARK: - Notes shown inline

/// Shows a note as written. Each paragraph takes its direction from its own first strong
/// character, so Hebrew and mixed Hebrew/English lines align correctly in the English UI.
struct CoachFeedbackBody: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(CoachFeedbackText.paragraphs(text).enumerated()), id: \.offset) { _, paragraph in
                let rtl = CoachFeedbackText.isRightToLeft(paragraph)
                Text(verbatim: paragraph)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            }
        }
    }
}

struct CoachFeedbackNoteRow: View {
    let note: CoachFeedback
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(verbatim: "You · " + CoachMetricFormat.isolate(Self.relative(note.createdAt)))
                    if note.editedAt != nil { Text("Edited") }
                }
                .font(.labelLG)
                .foregroundStyle(Color.textSecondary)
                CoachFeedbackBody(text: note.text)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit your feedback")
    }

    /// "now" for the first minute, then "5 min. ago" style, isolated so it keeps its order in RTL.
    static func relative(_ date: Date, now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        return now.timeIntervalSince(date) < 60 ? formatter.localizedString(fromTimeInterval: 0)
            : formatter.localizedString(for: date, relativeTo: now)
    }
}

/// The coach's notes on one run or week, plus the button that opens the composer.
struct CoachFeedbackSection: View {
    @ObservedObject var store: CoachFeedbackStore
    let target: CoachFeedbackTarget
    let weekStart: String
    let buttonTitle: String
    let open: (CoachFeedbackRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.notes(for: target)) { note in
                CoachFeedbackNoteRow(note: note) {
                    if let request = CoachFeedbackRequest.edit(note, weekStart: weekStart) { open(request) }
                }
            }
            Button {
                switch target {
                case .run(let id): open(.onRun(id, weekStart: weekStart))
                case .week(let start): open(.onWeek(start))
                }
            } label: {
                Label(buttonTitle, systemImage: "square.and.pencil")
                    .font(.buttonLabel)
                    .foregroundStyle(Color.accentPrimary)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }
}
