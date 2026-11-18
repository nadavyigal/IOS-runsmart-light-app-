import SwiftUI

struct CoachWelcomeDraft {
    static let starter = "Welcome to the group, {first name}! I'll be following your runs here. Let's build this together."
    static let maximumLength = 2000

    private let savedText: String?
    var text: String
    var confirmedStarter = false

    init(savedText: String?) {
        self.savedText = savedText
        text = savedText ?? Self.starter
    }

    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var offersStarterConfirmation: Bool { savedText == nil && trimmed == Self.starter }
    var canSave: Bool {
        guard trimmed.unicodeScalars.count <= Self.maximumLength else { return false }
        if let savedText { return trimmed != savedText }
        return !trimmed.isEmpty && (!offersStarterConfirmation || confirmedStarter)
    }
}

struct CoachWelcomeHint {
    var defaults: UserDefaults = .standard

    func shouldShow(ownerID: UUID, savedText: String?) -> Bool {
        savedText == nil && !defaults.bool(forKey: key(ownerID))
    }

    func consume(ownerID: UUID) { defaults.set(true, forKey: key(ownerID)) }

    private func key(_ ownerID: UUID) -> String { "coachWelcome.hintSeen.\(ownerID)" }
}

/// C12. The preview uses the same signed card and paragraph renderer as Today.
struct CoachWelcomeEditor: View {
    var athlete: CoachAthleteDestination?
    var service: any CoachWelcomeServing = SupabaseCoachWelcomeService()

    @Environment(\.dismiss) private var dismiss
    @State private var settings: CoachWelcomeSettings?
    @State private var draft = CoachWelcomeDraft(savedText: nil)
    @State private var loadFailed = false
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(athlete.map { "Only for \($0.name)" } ?? "Applies to new joiners from now on.")
                        .foregroundStyle(Color.textSecondary)

                    if let settings {
                        editor(settings)
                    } else if loadFailed {
                        Text("Couldn't load your welcome.")
                        Button("Retry") { Task { await load() } }
                            .frame(minWidth: 44, minHeight: 44)
                    } else {
                        ProgressView()
                            .accessibilityLabel("Loading welcome note")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Welcome note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .task { await load() }
    }

    private func editor(_ settings: CoachWelcomeSettings) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if settings.canEdit {
                TextEditor(text: messageText)
                    .frame(minHeight: 140)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Welcome message")
                    .disabled(isSaving)

                if draft.offersStarterConfirmation {
                    Toggle("Use this starter as written", isOn: $draft.confirmedStarter)
                        .frame(minHeight: 44)
                        .disabled(isSaving)
                }
                if draft.trimmed.unicodeScalars.count > CoachWelcomeDraft.maximumLength {
                    Text("Use 2,000 characters or fewer.")
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                Text("This athlete has already read their welcome.")
            }

            if !draft.trimmed.isEmpty {
                Text("Today preview")
                    .font(.headingMD)
                    .accessibilityAddTraits(.isHeader)
                let firstName = athlete?.name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "Yoni"
                CoachSignedCard(
                    title: CoachPresenceCopy.welcomeCard(settings.coachName),
                    text: draft.trimmed.replacingOccurrences(of: "{first name}", with: firstName),
                    coachName: settings.coachName
                ) { EmptyView() }
            }

            if let savedMessage {
                Text(savedMessage).foregroundStyle(Color.accentSuccess)
            }
            if settings.canEdit {
                if saveFailed {
                    Text("Couldn't save your welcome.")
                }
                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().accessibilityLabel("Saving welcome note")
                        } else {
                            Text(saveFailed ? "Retry" : "Save")
                        }
                    }
                    .frame(minWidth: 88, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentPrimary)
                .disabled(!canSave || isSaving)
            }
        }
    }

    private var messageText: Binding<String> {
        Binding(get: { draft.text }, set: { text in
            draft.text = text
            draft.confirmedStarter = false
            savedMessage = nil
            saveFailed = false
        })
    }

    private var canSave: Bool {
        draft.canSave && (athlete == nil || !draft.trimmed.isEmpty)
    }

    private func load() async {
        loadFailed = false
        do {
            let result = try await service.settings(athleteID: athlete?.athleteID)
            guard !Task.isCancelled else { return }
            draft = CoachWelcomeDraft(savedText: result.savedText)
            settings = result
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }

    private func save() async {
        guard canSave, !isSaving else { return }
        let text = draft.trimmed
        isSaving = true
        saveFailed = false
        defer { isSaving = false }

        do {
            try await service.save(text, athleteID: athlete?.athleteID)
            draft = CoachWelcomeDraft(savedText: text)
            savedMessage = if let athlete {
                "Saved. Only \(athlete.name) will see this welcome."
            } else if text.isEmpty {
                "Welcome note cleared."
            } else {
                "Saved. New athletes will see it on their first Today."
            }
        } catch {
            saveFailed = true
        }
    }
}
