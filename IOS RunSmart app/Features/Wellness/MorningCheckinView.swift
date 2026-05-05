import SwiftUI

struct MorningCheckinView: View {
    @Environment(\.runSmartServices) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var energy = 7.0
    @State private var soreness = 3.0
    @State private var mood = "Steady"
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var recovery: RecoverySnapshot = .loading
    @State private var wellness: WellnessSnapshot = .empty
    @State private var garminApprovalFailed = false

    private let moods = ["Strong", "Steady", "Tired", "Stressed"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentPrimary) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Morning check-in")
                    Text(hasGarminSignal ? "Approve Garmin readiness?" : "How ready do you feel before today’s training?")
                        .font(.headingLG)
                    Text(hasGarminSignal ? recovery.recommendation : "This adjusts workout intensity without storing medical records.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            if hasGarminSignal {
                ContentCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Garmin proposal", trailing: "Approve")
                        CheckinDetailLine(label: "Readiness", value: recovery.readiness > 0 ? "\(recovery.readiness)" : "--")
                        CheckinDetailLine(label: "Body Battery", value: recovery.bodyBattery > 0 ? "\(recovery.bodyBattery)" : "--")
                        CheckinDetailLine(label: "Sleep", value: recovery.sleep)
                        CheckinDetailLine(label: "HRV", value: recovery.hrv)
                        CheckinDetailLine(label: "Status", value: wellness.checkInStatus)
                    }
                }

                Button {
                    Task { await approveGarmin() }
                } label: {
                    Label(isSaving ? "Saving" : "Approve Garmin Check-In", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(NeonButtonStyle())
                .disabled(isSaving)

                if garminApprovalFailed {
                    Text("Garmin metrics are not fresh enough to approve. Use the manual check-in below.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.accentHeart)
                }
            }

            CheckinSlider(title: "Energy", value: $energy, tint: .accentSuccess)
            CheckinSlider(title: "Soreness", value: $soreness, tint: .accentEnergy)

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Mood")
                    HStack(spacing: 8) {
                        ForEach(moods, id: \.self) { option in
                            Button { mood = option } label: {
                                Text(option)
                                    .font(.labelSM)
                                    .tracking(1.0)
                                    .foregroundStyle(mood == option ? Color.black : Color.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(mood == option ? Color.accentPrimary : Color.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button {
                Task { await save() }
            } label: {
                Label(isSaving ? "Saving" : "Save Check-In", systemImage: "checkmark")
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(isSaving)

            if saveFailed {
                Text("Could not save check-in. Try again in a moment.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.accentHeart)
            }
        }
        .task {
            async let recoveryTask = services.recoverySnapshot()
            async let wellnessTask = services.wellnessSnapshot()
            (recovery, wellness) = await (recoveryTask, wellnessTask)
        }
    }

    private var hasGarminSignal: Bool {
        recovery.readiness > 0 || recovery.bodyBattery > 0 || recovery.hrv != "—" || recovery.sleep != "—"
    }

    private func approveGarmin() async {
        isSaving = true
        saveFailed = false
        garminApprovalFailed = false
        let saved = await services.approveGarminMorningCheckin()
        isSaving = false
        if saved {
            RunSmartHaptics.success()
            dismiss()
        } else {
            garminApprovalFailed = true
        }
    }

    private func save() async {
        isSaving = true
        saveFailed = false
        garminApprovalFailed = false
        let saved = await services.saveMorningCheckin(
            energy: Int(energy),
            soreness: Int(soreness),
            mood: mood,
            stress: nil,
            fatigue: nil,
            notes: nil
        )
        isSaving = false
        if saved {
            RunSmartHaptics.success()
            dismiss()
        } else {
            saveFailed = true
        }
    }
}

private struct CheckinDetailLine: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.bodyMD.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct CheckinSlider: View {
    var title: String
    @Binding var value: Double
    var tint: Color

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionLabel(title: title)
                    Text("\(Int(value))/10")
                        .font(.metricSM)
                        .foregroundStyle(tint)
                }
                Slider(value: $value, in: 1...10, step: 1)
                    .tint(tint)
            }
        }
    }
}
