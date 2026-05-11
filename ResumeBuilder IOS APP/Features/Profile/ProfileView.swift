import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var showPaywall = false
    @State private var latestOptimization: OptimizationHistoryItem?
    @State private var profileMessage: String?
    @State private var appeared = false

    private var email: String { appState.session?.email ?? "Signed in" }
    private var initials: String {
        let parts = email.split(separator: "@").first?.split(separator: ".") ?? []
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased().prefix(2).description
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {

                        // ── Hero header ──────────────────────────────────────
                        heroHeader
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : -8)

                        // ── Stats row ────────────────────────────────────────
                        statsRow
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .opacity(appeared ? 1 : 0)

                        // ── Sections ─────────────────────────────────────────
                        VStack(spacing: 14) {
                            latestResumeSection
                            if BackendConfig.isMonetizationEnabled {
                                creditsSection
                            }
                            accountSection
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)

                        Spacer(minLength: 100)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationBarHidden(true)
            .task {
                await loadLatestOptimization()
                withAnimation(.easeOut(duration: 0.5)) { appeared = true }
            }
            .sheet(isPresented: $showPaywall) {
                NavigationStack { PaywallView() }
                    .preferredColorScheme(.dark)
                    .tint(Theme.accent)
            }
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        ZStack(alignment: .bottom) {
            Theme.brandGradient
                .opacity(0.85)
                .frame(height: 160)
                .overlay(
                    RadialGradient(
                        colors: [Color.white.opacity(0.15), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 220
                    )
                )

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.bgPrimary)
                        .frame(width: 76, height: 76)
                        .shadow(color: Theme.accent.opacity(0.4), radius: 16, y: 6)

                    Text(initials.isEmpty ? "R" : initials)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                .offset(y: 38)

                Spacer().frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .padding(.bottom, 48)
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 3) {
                Text(email)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("Active account")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCell(
                value: latestOptimization != nil ? "1+" : "0",
                label: "Optimized",
                icon: "wand.and.stars",
                color: Theme.accent
            )
            statCell(
                value: latestOptimization.map { "\($0.matchScorePercent)%" } ?? "—",
                label: "Best ATS",
                icon: "gauge.medium",
                color: Theme.accentBlue
            )
            statCell(
                value: "∞",
                label: "Templates",
                icon: "paintbrush.fill",
                color: Theme.accentCyan
            )
        }
    }

    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Section: Latest Resume

    private var latestResumeSection: some View {
        ProfileSection(title: "Latest Resume", icon: "doc.text.fill", iconColor: Theme.accent) {
            if let opt = latestOptimization {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.accent.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "doc.richtext.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(opt.jobTitle ?? "Optimized resume")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(opt.company ?? "Tap Design tab to preview")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    ATSScorePill(score: opt.matchScorePercent)
                }
                .padding(14)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.title3)
                        .foregroundStyle(Theme.textTertiary)
                    Text(profileMessage ?? "No optimized resume yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(14)
            }
        }
    }

    // MARK: - Section: Credits

    private var creditsSection: some View {
        ProfileSection(title: "Credits", icon: "creditcard.fill", iconColor: Theme.accentBlue) {
            VStack(spacing: 0) {
                NavigationLink { CreditsView() } label: {
                    profileRow(icon: "list.bullet.rectangle", label: "View Credits", color: Theme.accentBlue)
                }
                .buttonStyle(.plain)

                Divider()
                    .background(Color.white.opacity(0.06))
                    .padding(.horizontal, 14)

                Button { showPaywall = true } label: {
                    profileRow(icon: "plus.circle.fill", label: "Buy Credits", color: Theme.accent, isAction: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Section: Account

    private var accountSection: some View {
        ProfileSection(title: "Account", icon: "person.crop.circle.fill", iconColor: Theme.textTertiary) {
            Button(role: .destructive) {
                appState.signOut()
            } label: {
                profileRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    label: "Sign Out",
                    color: .red,
                    isDestructive: true
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Row helper

    private func profileRow(
        icon: String,
        label: String,
        color: Color,
        isAction: Bool = false,
        isDestructive: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.subheadline.weight(isDestructive ? .medium : .regular))
                .foregroundStyle(isDestructive ? .red : Theme.textPrimary)
            Spacer()
            if !isDestructive {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(14)
    }

    // MARK: - Data

    @MainActor
    private func loadLatestOptimization() async {
        guard let token = appState.session?.accessToken else { return }
        do {
            let response: OptimizationHistoryResponse = try await appState.apiClient.get(
                endpoint: .optimizations,
                token: token
            )
            latestOptimization = response.allItems.first
            if latestOptimization == nil {
                profileMessage = "Tailor a resume to a job to see it here."
            }
        } catch {
            profileMessage = error.localizedDescription
        }
    }
}

// MARK: - Profile Section Container

private struct ProfileSection<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .kerning(0.8)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
    }
}
