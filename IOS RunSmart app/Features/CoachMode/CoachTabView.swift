import SwiftUI
import UIKit

/// Coach tab root (UX spec C1, empty state for now). The athlete list arrives in Story 2.3.
struct CoachTabView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                RunSmartTopBar(title: "Coach")

                ContentCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No athletes yet.")
                            .font(.headingMD)
                            .foregroundStyle(Color.textPrimary)
                        Text("Share your invite code to get started.")
                            .font(.bodyMD)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }

                CoachInviteSection()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 140)
        }
    }
}

/// Invite section (UX spec C4): the code, a share link, Copy code, Copy link and Share.
struct CoachInviteSection: View {
    @StateObject private var viewModel: CoachInviteViewModel
    @State private var copiedLabel: String?

    init(repository: any CoachModeRepository = SupabaseCoachModeRepository()) {
        _viewModel = StateObject(wrappedValue: CoachInviteViewModel(repository: repository))
    }

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 14) {
                // Sentence case, no tracking: the spec bans all-caps labels (Hebrew has none).
                Text("Invite")
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                switch viewModel.state {
                case .loading:
                    ProgressView()
                        .tint(Color.accentPrimary)
                        .frame(maxWidth: .infinity, minHeight: 96)
                        .accessibilityLabel("Loading your invite")
                case .loaded(let invite):
                    loaded(invite)
                case .failed:
                    failed
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await viewModel.load() }
    }

    private func loaded(_ invite: CoachInvite) -> some View {
        let link = invite.link()
        return VStack(alignment: .leading, spacing: 14) {
            // The code is an LTR, letter-spaced block so it reads aloud and in RTL layouts the same way.
            Text(invite.code)
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .tracking(10)
                .foregroundStyle(Color.accentPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .environment(\.layoutDirection, .leftToRight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Invite code \(invite.code.map(String.init).joined(separator: " "))")
                .accessibilityIdentifier("coach-invite-code")

            Text(link.absoluteString)
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
                .environment(\.layoutDirection, .leftToRight)
                .textSelection(.enabled)
                .accessibilityIdentifier("coach-invite-link")

            HStack(spacing: 10) {
                copyButton("Copy code", copied: "Code copied", value: invite.code)
                copyButton("Copy link", copied: "Link copied", value: link.absoluteString)
            }

            ShareLink(item: invite.shareMessage()) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(NeonButtonStyle())
            .accessibilityIdentifier("coach-invite-share")

            // Always present so the layout doesn't jump; read aloud when it changes.
            Text(copiedLabel ?? " ")
                .font(.labelLG)
                .foregroundStyle(Color.accentSuccess)
                .accessibilityHidden(copiedLabel == nil)
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Couldn't load your invite.")
                .font(.bodyLG)
                .foregroundStyle(Color.textPrimary)
            Button("Retry") {
                Task { await viewModel.load() }
            }
            .buttonStyle(NeonButtonStyle())
            .accessibilityIdentifier("coach-invite-retry")
        }
    }

    private func copyButton(_ title: String, copied: String, value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            RunSmartHaptics.light()
            copiedLabel = copied
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if copiedLabel == copied { copiedLabel = nil }
            }
        } label: {
            Text(title)
                .font(.buttonLabel)
                .foregroundStyle(Color.accentPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: RunSmartRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RunSmartRadius.md, style: .continuous)
                        .stroke(Color.accentPrimary.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
