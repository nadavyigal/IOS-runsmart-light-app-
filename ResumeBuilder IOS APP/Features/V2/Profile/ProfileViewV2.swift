import SwiftUI

struct ProfileViewV2: View {
    @Environment(AppState.self) private var appState
    @State private var showAuth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    GreetingHeader(
                        name: firstName,
                        screenTitle: "Profile"
                    )
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.xl)

                    accountCard
                    runnerProfileCard
                    integrationsCard
                    privacyCard

                    if appState.isAuthenticated {
                        signOutButton
                    } else {
                        signInButton
                    }

                    Spacer(minLength: 100)
                }
            }
            .scrollIndicators(.hidden)
            .screenBackground(showRadialGlow: false)
            .navigationBarHidden(true)
            .sheet(isPresented: $showAuth) {
                OnboardingView(viewModel: OnboardingViewModel(appState: appState))
            }
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label("Account", systemImage: "person.fill")
                .font(.appCaption)
                .foregroundStyle(AppColors.textSecondary)

            HStack(spacing: AppSpacing.md) {
                Circle()
                    .fill(AppColors.gradientMid.opacity(0.25))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(firstName.prefix(1).uppercased())
                            .font(.appSubheadline)
                            .foregroundStyle(AppColors.gradientMid)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.session?.email ?? "Guest mode")
                        .font(.appSubheadline)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(appState.isAuthenticated ? "Runner profile" : "Sign in to save your running setup")
                        .font(.appCaption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: AppRadii.lg)
        .padding(.horizontal, AppSpacing.lg)
    }

    private var runnerProfileCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label("Runner Setup", systemImage: "figure.run")
                .font(.appCaption)
                .foregroundStyle(AppColors.textSecondary)

            settingRow(icon: "target", title: "Goal", value: "Pending")
            settingRow(icon: "calendar", title: "Training days", value: "Pending")
            settingRow(icon: "speedometer", title: "Current level", value: "Pending")

            GradientButton(
                title: "Set Running Goal",
                icon: "target"
            ) {
                if !appState.isAuthenticated {
                    showAuth = true
                }
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: AppRadii.lg)
        .padding(.horizontal, AppSpacing.lg)
    }

    private var integrationsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label("Connections", systemImage: "link")
                .font(.appCaption)
                .foregroundStyle(AppColors.textSecondary)

            settingRow(icon: "heart.text.square", title: "Apple Health / HealthKit", value: "Not connected")
            settingRow(icon: "antenna.radiowaves.left.and.right", title: "Garmin", value: "Not connected")
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: AppRadii.lg)
        .padding(.horizontal, AppSpacing.lg)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label("Privacy", systemImage: "lock.shield.fill")
                .font(.appCaption)
                .foregroundStyle(AppColors.textSecondary)

            Text("Health and location permissions will be requested only when the approved RunSmart tracking and integration stories are implemented.")
                .font(.appBody)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: AppRadii.lg)
        .padding(.horizontal, AppSpacing.lg)
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            appState.signOut()
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
            .font(.appSubheadline)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, minHeight: 50)
            .glassCard(cornerRadius: AppRadii.lg)
        }
        .buttonStyle(GradientButtonStyle())
        .padding(.horizontal, AppSpacing.lg)
    }

    private var signInButton: some View {
        GradientButton(title: "Sign In", icon: "person.crop.circle.badge.plus") {
            showAuth = true
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    private func settingRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.gradientMid)
                .frame(width: 22)

            Text(title)
                .font(.appBody)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Text(value)
                .font(.appCaption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(AppSpacing.md)
        .background(AppColors.glassTint, in: RoundedRectangle(cornerRadius: AppRadii.md, style: .continuous))
    }

    private var firstName: String {
        guard let email = appState.session?.email,
              let local = email.components(separatedBy: "@").first else { return "there" }
        return local.capitalized
    }
}

#Preview {
    ProfileViewV2()
        .environment(AppState())
}
