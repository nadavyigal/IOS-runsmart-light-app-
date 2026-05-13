import SwiftUI

struct RunView: View {
    @Bindable var designViewModel: DesignViewModel
    var onPreview: (() -> Void)? = nil

    @State private var showCurrentRunFlow = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    runActionCard
                    manualLogCard
                    currentRunFlowCard
                    Spacer(minLength: 96)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .scrollIndicators(.hidden)
            .screenBackground(showRadialGlow: true)
            .navigationBarHidden(true)
            .sheet(isPresented: $showCurrentRunFlow) {
                RedesignResumeView(
                    viewModel: designViewModel,
                    onPreview: onPreview
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "figure.run")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accentCyan)
                Text("RUN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.accentCyan)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppColors.accentCyan.opacity(0.12), in: Capsule())

            Text("Start moving")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)

            Text("The future home for GPS tracking, manual logs, and post-run review.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .lineSpacing(2)
        }
    }

    private var runActionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.accentCyan.opacity(0.16))
                        .frame(width: 52, height: 52)
                    Image(systemName: "location.north.line.fill")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(AppColors.accentCyan)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Start GPS run")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("GPS tracking will connect here after location permissions, real-device validation, and background behavior are approved.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
            } label: {
                Label("Coming soon", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(AppColors.textSecondary)
                    .background(AppColors.glassTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(true)
        }
        .padding(18)
        .background(AppColors.backgroundMid, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColors.glassStroke, lineWidth: 1)
        )
    }

    private var manualLogCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.accentSky.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(AppColors.accentSky)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Log manual run")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("Manual run entry stays unavailable until the run data model is approved.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text("Soon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.glassTint, in: Capsule())
        }
        .padding(18)
        .background(AppColors.backgroundMid, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColors.glassStroke, lineWidth: 1)
        )
    }

    private var currentRunFlowCard: some View {
        Button {
            showCurrentRunFlow = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.accentViolet.opacity(0.16))
                        .frame(width: 48, height: 48)
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(AppColors.accentViolet)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Current design flow")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Open the existing redesign flow while this tab is migrated toward running actions.")
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
        .accessibilityHint("Opens the existing design flow.")
    }
}

#Preview {
    RunView(designViewModel: DesignViewModel(optimizationId: nil))
        .environment(AppState())
}
