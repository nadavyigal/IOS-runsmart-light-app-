import SwiftUI

struct RecoveryDashboardView: View {
    private let signals: [(title: String, value: String, detail: String, tint: Color, symbol: String)] = [
        ("HRV", "64 ms", "+8 vs baseline", .accentHeart, "waveform.path.ecg"),
        ("Sleep", "7h 42m", "82% quality", .accentRecovery, "moon.fill"),
        ("Body", "Ready", "Low stress", .accentSuccess, "heart.circle.fill"),
        ("Load", "Balanced", "No spike", .accentPrimary, "chart.bar.fill")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentSuccess) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Recovery dashboard", trailing: "Today")
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("82")
                                .font(.displayXL)
                                .monospacedDigit()
                                .foregroundStyle(Color.textPrimary)
                                .displayTightTracking()
                            Text("READY TO TRAIN")
                                .font(.labelSM)
                                .tracking(1.2)
                                .foregroundStyle(Color.accentSuccess)
                        }
                        Spacer()
                        ProgressRing(value: 0.82, lineWidth: 12, icon: "bolt.fill", tint: .accentSuccess)
                            .frame(width: 118, height: 118)
                            .runSmartPulse(scale: 1.018)
                    }
                    Text("Green light for quality work. Keep the first third controlled and use breathing as the limiter.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(signals, id: \.title) { signal in
                    RecoverySignalTile(title: signal.title, value: signal.value, detail: signal.detail, tint: signal.tint, symbol: signal.symbol)
                }
            }

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Coach read")
                    RecoveryReadRow(title: "Train", detail: "Tempo builder is still appropriate.", tint: .accentSuccess)
                    RecoveryReadRow(title: "Watch", detail: "If legs feel heavy after warm-up, cap at steady effort.", tint: .accentPrimary)
                    RecoveryReadRow(title: "Recover", detail: "Add 10 minutes mobility after the run.", tint: .accentRecovery)
                }
            }
        }
    }
}

private struct RecoverySignalTile: View {
    var title: String
    var value: String
    var detail: String
    var tint: Color
    var symbol: String

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.metricSM)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text(title.uppercased())
                    .font(.labelSM)
                    .tracking(1.1)
                    .foregroundStyle(Color.textSecondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RecoveryReadRow: View {
    var title: String
    var detail: String
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title.uppercased())
                .font(.labelSM)
                .tracking(1.1)
                .foregroundStyle(tint)
                .frame(width: 70, alignment: .leading)
            Text(detail)
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
        }
    }
}
