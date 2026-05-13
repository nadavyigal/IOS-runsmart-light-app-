import SwiftUI

struct TodayView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    todayFocusCard
                    coachCueCard
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
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accentCyan)
                Text("TODAY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.accentCyan)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppColors.accentCyan.opacity(0.12), in: Capsule())

            Text("Good \(dayPart), \(firstName)")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)

            Text("One clear next action for today's training.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(2)
        }
    }

    private var todayFocusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.accentSky.opacity(0.16))
                        .frame(width: 48, height: 48)
                    Image(systemName: "figure.run")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppColors.accentSky)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("No plan yet")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Set a running goal to see your workout, readiness cue, and coach note here.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
                .background(Color.white.opacity(0.08))

            HStack(spacing: 12) {
                focusMetric(icon: "calendar", title: "Plan", value: "Pending")
                focusMetric(icon: "heart.text.square", title: "Readiness", value: "Pending")
            }
        }
        .padding(18)
        .background(AppColors.backgroundMid, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColors.glassStroke, lineWidth: 1)
        )
    }

    private var coachCueCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.accentViolet.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: "sparkles")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppColors.accentViolet)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Coach cue")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("Connect a goal and recent activity to receive a short daily training recommendation.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(18)
        .background(AppColors.backgroundMid, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColors.glassStroke, lineWidth: 1)
        )
    }

    private func focusMetric(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.accentCyan)
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

    private var firstName: String {
        guard let email = appState.session?.email,
              let local = email.components(separatedBy: "@").first,
              !local.isEmpty else { return "there" }
        return local.capitalized
    }

    private var dayPart: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "morning"
        case 12..<18: return "afternoon"
        default: return "evening"
        }
    }

}

#Preview {
    TodayView()
        .environment(AppState())
}
