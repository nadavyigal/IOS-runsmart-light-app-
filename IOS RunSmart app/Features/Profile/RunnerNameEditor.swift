import SwiftUI

/// The name input used by onboarding and the name sheet.
struct RunnerNameField: View {
    @Binding var name: String
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What should we call you?")
                .font(.bodyMD.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            TextField("Your first name", text: $name)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(onSubmit)
                .onChange(of: name) { _, newValue in
                    if newValue.count > RunnerName.maxLength {
                        name = String(newValue.prefix(RunnerName.maxLength))
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("runnerName.field")
        }
    }
}

/// Sheet to add or change the runner's name, from Today and Settings.
struct RunnerNameSheet: View {
    @EnvironmentObject private var session: SupabaseSession
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isSaving = false
    @State private var saveFailed = false

    init(currentName: String) {
        _name = State(initialValue: RunnerName.forSaving(currentName))
    }

    private var canSave: Bool { RunnerName.resolved(name) != nil && !isSaving }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                RunnerNameField(name: $name, onSubmit: save)
                Text("Shown on Today, and to your coach if you have one.")
                    .font(.caption)
                    .foregroundStyle(Color.mutedText)
                if saveFailed {
                    Text("Couldn't save your name. Check your connection and try again.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RunSmartBrand.error)
                        .accessibilityIdentifier("runnerName.error")
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
                        .accessibilityIdentifier("runnerName.save")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        saveFailed = false
        Task {
            let saved = await session.saveDisplayName(name)
            isSaving = false
            if saved {
                dismiss()
            } else {
                saveFailed = true
            }
        }
    }
}
