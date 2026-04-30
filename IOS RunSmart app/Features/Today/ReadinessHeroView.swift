import SwiftUI

struct ReadinessHeroView: View {
    var recommendation: TodayRecommendation
    var onTap: () -> Void

    private var readinessValue: Double {
        Double(recommendation.readiness) / 100
    }

    private var readinessTint: Color {
        switch recommendation.readiness {
        case 80...100: return .accentSuccess
        case 55..<80: return .accentPrimary
        default: return .accentHeart
        }
    }

    var body: some View {
        Button(action: onTap) {
            HeroCard(accent: readinessTint, padding: 18) {
                VStack(spacing: 18) {
                    SectionLabel(title: "Readiness", trailing: "Tap for recovery")

                    ZStack {
                        ProgressRing(value: readinessValue, lineWidth: 13, icon: "bolt.fill", tint: readinessTint)
                            .frame(width: 148, height: 148)
                            .runSmartPulse(scale: 1.018)
                        VStack(spacing: 0) {
                            Text("\(recommendation.readiness)")
                                .font(.displayXL)
                                .monospacedDigit()
                                .foregroundStyle(Color.textPrimary)
                                .displayTightTracking()
                            Text("READY TO TRAIN")
                                .font(.labelSM)
                                .tracking(1.2)
                                .foregroundStyle(readinessTint)
                        }
                    }

                    HStack(spacing: 10) {
                        readinessMetric("HRV", recommendation.hrv, "waveform.path.ecg", .accentHeart)
                        readinessMetric("Sleep", recommendation.recovery, "moon.fill", .accentRecovery)
                        readinessMetric("Recovery", recommendation.readinessLabel, "heart.circle.fill", readinessTint)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func readinessMetric(_ title: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        CompactCard {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.metricXS)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title.uppercased())
                    .font(.labelSM)
                    .tracking(1.0)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
