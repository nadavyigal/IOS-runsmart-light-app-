import SwiftUI

/// Reusable inside run preferences. Weight is optional and requested only here.
struct RunnerWeightSettingsView: View {
    @ObservedObject private var weight = RunnerWeightStore.shared
    @State private var enteredWeight = ""
    @State private var message: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Calorie estimate")
                Text("Add your weight once to estimate active calories while running. Weight stays on this device.")
                    .font(.callout)
                    .foregroundStyle(Color.mutedText)

                if let kilograms = weight.weightKg {
                    Text("\(kilograms.formatted(.number.precision(.fractionLength(0...1)))) kg · \(weight.sourceLabel ?? "Your weight")")
                        .font(.callout.weight(.semibold))
                }

                HStack {
                    TextField("Weight in kg", text: $enteredWeight)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Weight in kilograms")
                    Button("Save") { saveManualWeight() }
                        .buttonStyle(.bordered)
                }

                Button {
                    Task {
                        await weight.requestHealthWeight()
                        message = weight.healthWeightKg == nil
                            ? "No weight was available from Apple Health. You can enter it above."
                            : "Using your latest Apple Health weight."
                    }
                } label: {
                    Label(weight.isReadingHealth ? "Reading weight…" : "Use Apple Health weight", systemImage: "heart.fill")
                }
                .disabled(weight.isReadingHealth)
                .accessibilityHint("Requests read access to body mass through HealthKit for calorie estimates.")

                if weight.healthWeightKg != nil {
                    Button("Use entered weight instead") {
                        weight.stopUsingHealthWeight()
                        message = nil
                    }
                }

                if weight.manualWeightKg != nil {
                    Button("Remove entered weight", role: .destructive) {
                        weight.clearManualWeight()
                        enteredWeight = ""
                        message = nil
                    }
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Color.mutedText)
                        .accessibilityIdentifier("weightSettingsMessage")
                }
            }
        }
        .onAppear {
            if let kilograms = weight.manualWeightKg {
                enteredWeight = kilograms.formatted(.number.precision(.fractionLength(0...1)))
            }
        }
    }

    private func saveManualWeight() {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        guard let value = formatter.number(from: enteredWeight)?.doubleValue,
              weight.setManualWeightKg(value) else {
            message = "Enter a valid weight in kilograms."
            return
        }
        enteredWeight = value.formatted(.number.precision(.fractionLength(0...1)))
        message = weight.healthWeightKg == nil
            ? "Weight saved for calorie estimates."
            : "Weight saved as a fallback. Apple Health weight is currently used."
    }
}
