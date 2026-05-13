import SwiftUI

struct GarminWellnessViews: View {
    @Environment(\.runSmartServices) private var services
    @State private var recovery: RecoverySnapshot = .loading
    @State private var wellness: WellnessSnapshot = .empty

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentRecovery) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Garmin wellness")
                    Text(sourceTitle)
                        .font(.headingLG)
                    Text(wellness.checkInStatus)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            WellnessPanel(title: "Readiness", value: recovery.readiness > 0 ? "\(recovery.readiness)" : "--", detail: recovery.recommendation, tint: .accentSuccess, symbol: "bolt.heart.fill")
            WellnessPanel(title: "Body Battery", value: recovery.bodyBattery > 0 ? "\(recovery.bodyBattery)" : "--", detail: wellness.hydration, tint: .accentPrimary, symbol: "battery.75percent")
            WellnessPanel(title: "Sleep", value: recovery.sleep, detail: "Latest Garmin sleep value when connected.", tint: .accentRecovery, symbol: "bed.double.fill")
            WellnessPanel(title: "HRV", value: recovery.hrv, detail: "Latest synced HRV value.", tint: .accentHeart, symbol: "waveform.path.ecg")
            WellnessPanel(title: "Manual Check-In", value: wellness.mood, detail: "Soreness \(wellness.soreness)", tint: .accentEnergy, symbol: "checklist.checked")
        }
        .task {
            async let recoveryTask = services.recoverySnapshot()
            async let wellnessTask = services.wellnessSnapshot()
            (recovery, wellness) = await (recoveryTask, wellnessTask)
        }
    }

    private var sourceTitle: String {
        recovery.readiness > 0 ? "Synced health signals" : "No Garmin recovery data yet"
    }
}

private struct WellnessPanel: View {
    var title: String
    var value: String
    var detail: String
    var tint: Color
    var symbol: String

    var body: some View {
        ContentCard {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headingMD)
                    Text(detail)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Text(value)
                    .font(.metricSM)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
