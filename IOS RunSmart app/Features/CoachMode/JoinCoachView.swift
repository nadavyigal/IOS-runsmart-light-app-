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
                case .consent(let coach):
                    consent(coach)
                }
            }
        }
        .onChange(of: model.joinedCoach) { _, coach in
            guard let coach else { return }
            coachLinks.noteJoined(coach)
            router.selectedTab = .today
            dismiss()
        }
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

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(Color.accentHeart)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await model.continueTapped(isSignedIn: session.isAuthenticated) }
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
                    Task { await model.share() }
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
