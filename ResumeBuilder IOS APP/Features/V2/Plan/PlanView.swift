import SwiftUI

struct PlanView: View {
    @Bindable var tailorViewModel: TailorViewModel

    @State private var showCurrentPlanFlow = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    planStatusCard
                    currentPlanFlowCard
                    Spacer(minLength: 96)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
            .screenBackground(showRadialGlow: true)
            .navigationBarHidden(true)
            .sheet(isPresented: $showCurrentPlanFlow) {
                TailorView(viewModel: tailorViewModel)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accentSky)
                Text("PLAN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.accentSky)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppColors.accentSky.opacity(0.12), in: Capsule())

            Text("Training ahead")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)

            Text("A dedicated place for weekly structure, goals, and upcoming sessions.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(2)
        }
    }

    private var planStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.accentSky.opacity(0.16))
                        .frame(width: 48, height: 48)
                    Image(systemName: "map.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(AppColors.accentSky)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("No active training plan")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Goal setup and generated workouts will live here when the approved planning model is connected.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
                .background(Color.white.opacity(0.08))

            HStack(spacing: 12) {
                planMetric(icon: "figure.run", title: "This week", value: "Pending")
                planMetric(icon: "target", title: "Goal", value: "Pending")
            }
        }
        .padding(18)
        .background(AppColors.backgroundMid, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColors.glassStroke, lineWidth: 1)
        )
    }

    private var currentPlanFlowCard: some View {
        Button {
            showCurrentPlanFlow = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.accentViolet.opacity(0.16))
                        .frame(width: 48, height: 48)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(AppColors.accentViolet)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Current improve flow")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Open the existing optimization flow while Plan is migrated toward running workouts.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(18)
            .background(AppColors.backgroundMid, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppColors.glassStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the existing improve flow.")
    }

    private func planMetric(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.accentSky)
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
    PlanView(tailorViewModel: TailorViewModel())
        .environment(AppState())
}
