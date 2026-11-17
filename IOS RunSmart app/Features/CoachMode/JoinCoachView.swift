import SwiftUI

/// A1 (enter a code) and A3 (consent). Share creates the link; Not now creates nothing.
struct JoinCoachView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SupabaseSession
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var coachLinks: CoachLinkStore

    @StateObject private var model: JoinCoachViewModel

    init(repository: any CoachLinkRepository = SupabaseCoachLinkRepository()) {
        _model = StateObject(wrappedValue: JoinCoachViewModel(repository: repository))
    }

    var body: some View {
        Group {
            if !session.isAuthenticated {
                Text("Sign in to join a coach.")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
            } else {
                switch model.phase {
                case .enterCode:
                    codeEntry
                case .resolvingLink:
                    consentSkeleton
                case .consent(let coach, _):
                    consent(coach)
                }
            }
        }
        .onAppear(perform: consumeInviteIfNeeded)
        .onChange(of: coachLinks.pendingInvite) { _, _ in
            consumeInviteIfNeeded()
        }
    }

    /// One-shot. A valid link fills the code and looks it up; a bad link shows the hint.
    private func consumeInviteIfNeeded() {
        guard let pending = coachLinks.pendingInvite else { return }
        coachLinks.pendingInvite = nil
        model.consumePendingInvite(pending)
        guard case .code = pending else { return }
        let athleteID = session.isAuthenticated ? session.currentUserID : nil
        Task { await model.resolveFromLink(athleteID: athleteID) }
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Join a coach")
                .font(.displayMD)
            TextField("Enter code", text: $model.code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(14)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(model.isWorking)
                .accessibilityLabel("Enter code")

            if model.showsEntryHint {
                Text(CoachConsentCopy.unresolvedLinkHint)
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier("Enter your coach's code")
            }

            // System paste control. iOS titles it "Paste"; the accessibility name is the story's "Paste code".
            // Reading UIPasteboard here would show the silent-paste warning, so this control is the only reader.
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                model.applyPastedText(text)
            }
            .accessibilityLabel("Paste code")

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(Color.accentHeart)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                let athleteID = session.isAuthenticated ? session.currentUserID : nil
                Task { await model.continueTapped(athleteID: athleteID) }
            } label: {
                if model.isWorking {
                    ProgressView()
                } else {
                    Text("Continue")
                }
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(model.isWorking)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Placeholder of A3 while lookup_invite runs for a link. The typed Continue path keeps its spinner.
    private var consentSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.surfaceElevated)
                .frame(width: 220, height: 28)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.surfaceElevated)
                        .frame(maxWidth: .infinity)
                        .frame(height: 14)
                }
            }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.surfaceElevated)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.surfaceElevated)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading coach")
    }

    private func consent(_ coach: CoachLookup) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(CoachConsentCopy.title(coach: coach.displayName))
                .font(.displayMD)
            Text(CoachConsentCopy.body(coach: coach.displayName))
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(Color.accentHeart)
            }

            HStack(spacing: 12) {
                Button {
                    guard let athleteID = session.currentUserID else { return }
                    Task {
                        await model.share(athleteID: athleteID)
                        guard session.isAuthenticated, session.currentUserID == athleteID,
                              let link = model.joinedCoach else { return }
                        coachLinks.noteJoined(link, userID: athleteID)
                        router.selectedTab = .today
                        dismiss()
                    }
                } label: {
                    Text("Share")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textPrimary)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))
                .disabled(model.isWorking)
                .accessibilityLabel("Share")

                Button {
                    model.notNow()
                } label: {
                    Text("Not now")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textPrimary)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))
                .disabled(model.isWorking)
                .accessibilityLabel("Not now")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
