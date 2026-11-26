import SwiftUI

/// Coach > menu > Your name. Athletes see this name in My coach, notes and notifications.
struct CoachDisplayNameSheet: View {
    var service: any CoachDisplayNameSaving = SupabaseCoachDisplayNameService()
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isSaving = false
    @State private var saveFailed = false

    init(currentName: String?, service: any CoachDisplayNameSaving = SupabaseCoachDisplayNameService(),
         onSaved: @escaping (String) -> Void) {
        self.service = service
        self.onSaved = onSaved
        _name = State(initialValue: CoachDisplayName.resolved(currentName) ?? "")
    }

    private var canSave: Bool { CoachDisplayName.forSaving(name) != nil && !isSaving }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your name as a coach")
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                TextField("For example, Coach Dana", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(save)
                    .onChange(of: name) { _, newValue in
                        let capped = CoachDisplayName.capped(newValue)
                        if capped != newValue { name = capped }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("coachName.field")
                Text("Your athletes see this in My coach, your notes and notifications.")
                    .font(.caption)
                    .foregroundStyle(Color.mutedText)
                if saveFailed {
                    Text("Couldn't save your name. Check your connection and try again.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RunSmartBrand.error)
                        .accessibilityIdentifier("coachName.error")
                }
                Spacer()
            }
            .padding(20)
            .background(Color.surfaceBase.ignoresSafeArea())
            .navigationTitle("Your name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("coachName.save")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let value = CoachDisplayName.forSaving(name), !isSaving else { return }
        isSaving = true
        saveFailed = false
        Task {
            do {
                let stored = try await service.save(value)
                isSaving = false
                onSaved(stored)
                dismiss()
            } catch {
                isSaving = false
                saveFailed = true
            }
        }
    }
}

/// Shown on the Coach tab while the coach has no name, so athletes never see "Your coach".
struct CoachDisplayNameCard: View {
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentPrimary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Add the name your athletes see")
                    .font(.bodyLG.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Without it, athletes see \u{201C}Your coach\u{201D} on your notes.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add name", action: onAdd)
                    .font(.bodyMD.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(Color.accentPrimary)
                    .accessibilityIdentifier("coachName.add")
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coachName.card")
    }
}
