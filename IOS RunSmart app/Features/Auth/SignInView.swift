import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject private var session: SupabaseSession
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var currentNonce = AppleSignInHelper.randomNonce()
    @State private var legalDocument: LegalDocument?

    /// First-screen promise pills (WP-44 S1). The audit (§4 Risk 2, §9) flagged
    /// "Run guidance and cue previews" as feature-speak and the HealthKit bullet
    /// as compliance-speak; a first-time user should see the daily answer the
    /// app actually sells. Static so copy is testable.
    static let featurePills: [(symbol: String, text: String)] = [
        ("sun.max.fill", "Know exactly what to run today"),
        ("calendar", "A plan that adapts to your runs"),
        ("heart.fill", "Works with Apple Health"),
    ]

    /// Terms/Privacy present in-app (WP-44 S6) instead of ejecting to Safari.
    enum LegalDocument: String, Identifiable {
        case terms, privacy

        var id: String { rawValue }

        var url: URL {
            switch self {
            case .terms: ExternalURLs.terms
            case .privacy: ExternalURLs.privacy
            }
        }
    }

    var body: some View {
        ZStack {
            RunSmartBackground()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 28) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.lime.opacity(0.15))
                                .frame(width: 100, height: 100)
                                .shadow(color: Color.lime.opacity(0.5), radius: 28)
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 46, weight: .black))
                                .foregroundStyle(Color.lime)
                        }

                        Text("RunSmart")
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Personal coaching before and after runs.\nSmart reports. Adaptive plan guidance.")
                            .font(.subheadline)
                            .foregroundStyle(Color.mutedText)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        ForEach(Self.featurePills, id: \.text) { pill in
                            FeaturePill(symbol: pill.symbol, text: pill.text)
                        }
                    }
                }

                Spacer()

                VStack(spacing: 14) {
                    if let error = errorMessage ?? session.lastAuthError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if isSigningIn {
                        ProgressView()
                            .tint(Color.lime)
                            .scaleEffect(1.2)
                    } else {
                        SignInWithAppleButton(.signIn) { request in
                            // Fresh nonce per attempt — store raw, send hashed to Apple
                            currentNonce = AppleSignInHelper.randomNonce()
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = AppleSignInHelper.sha256(currentNonce)
                        } onCompletion: { result in
                            // Use the credential Apple just gave us — do NOT create a second
                            // ASAuthorizationController; that is what caused the concurrency warning.
                            Task { @MainActor in await handleAppleResult(result) }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(spacing: 4) {
                        Text("By continuing you agree to our")
                            .foregroundStyle(Color.mutedText)

                        HStack(spacing: 4) {
                            Button("Terms of Service") { legalDocument = .terms }
                            Text("and")
                                .foregroundStyle(Color.mutedText)
                            Button("Privacy Policy") { legalDocument = .privacy }
                        }
                        .fontWeight(.semibold)
                    }
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .tint(Color.lime)
                    .padding(.horizontal, 24)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $legalDocument) { document in
            SafariView(url: document.url)
                .ignoresSafeArea()
        }
    }

    @MainActor
    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                throw AppleSignInError.invalidCredential
            }
            try await session.signInWithApple(
                idToken: idToken,
                nonce: currentNonce,
                appleDisplayName: appleDisplayName(from: credential.fullName),
                appleEmail: credential.email
            )
            Analytics.trackSignInCompleted(method: "apple")
        } catch let error as NSError
            where error.domain == ASAuthorizationError.errorDomain
               && error.code == ASAuthorizationError.canceled.rawValue {
            // User dismissed the sheet — not an error
        } catch {
            errorMessage = Self.humanReadableAppleSignInError(for: error)
            Analytics.trackSignInFailed(error: error)
        }
    }

    /// Maps Apple sign-in failures to user-facing copy. Never forwards
    /// `NSError.localizedDescription` — that surfaces raw strings like
    /// "com.apple.AuthenticationServices.AuthorizationError error 1000" to a
    /// first-time user. `.canceled` returns nil (user backed out silently).
    static func humanReadableAppleSignInError(for error: Error) -> String? {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain,
           nsError.code == ASAuthorizationError.canceled.rawValue {
            return nil
        }
        return "Apple sign-in didn't finish. Nothing was created — tap to try again."
    }

    private func appleDisplayName(from fullName: PersonNameComponents?) -> String? {
        guard let fullName else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .medium
        let name = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

private struct FeaturePill: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.bold())
                .foregroundStyle(Color.lime)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.86))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hairline, lineWidth: 0.5))
        .padding(.horizontal, 28)
    }
}
