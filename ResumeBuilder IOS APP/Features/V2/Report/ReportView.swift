import SwiftUI

struct ReportView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    reportSummaryCard
                    adherenceCard
                    Spacer(minLength: 96)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
            .screenBackground(showRadialGlow: true)
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accentTeal)
                Text("REPORT")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.accentTeal)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppColors.accentTeal.opacity(0.12), in: Capsule())

            Text("Progress history")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)

            Text("A separate home for recent runs, trends, adherence, and recovery history.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(2)
        }
    }

    private var reportSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.accentTeal.opacity(0.16))
                        .frame(width: 48, height: 48)
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(AppColors.accentTeal)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("No run report yet")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Completed workouts and progress trends will appear here once running data is approved and connected.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
                .background(Color.white.opacity(0.08))

            HStack(spacing: 12) {
                reportMetric(icon: "clock.arrow.circlepath", title: "Recent", value: "Pending")
                reportMetric(icon: "waveform.path.ecg", title: "Recovery", value: "Pending")
            }
        }
        .padding(18)
        .background(AppColors.backgroundMid, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColors.glassStroke, lineWidth: 1)
        )
    }

    private var adherenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Plan adherence", systemImage: "checkmark.seal.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text("Weekly completion, distance trend, and recovery history will appear here after run data is connected.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                reportMetric(icon: "checkmark.circle", title: "Complete", value: "Pending")
                reportMetric(icon: "arrow.up.right", title: "Trend", value: "Pending")
            }
        }
        .padding(18)
        .background(AppColors.backgroundMid, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColors.glassStroke, lineWidth: 1)
        )
    }

    private func reportMetric(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.accentTeal)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.glassTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    ReportView()
        .environment(AppState())
}
