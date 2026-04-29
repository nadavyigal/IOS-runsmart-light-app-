import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject private var session: SupabaseSession
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var currentNonce = AppleSignInHelper.randomNonce()

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

                        Text("Your AI-powered running coach.\nPersonalized plans. Real results.")
                            .font(.subheadline)
                            .foregroundStyle(Color.mutedText)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 12) {
                        FeaturePill(symbol: "waveform", text: "Live AI coaching during runs")
                        FeaturePill(symbol: "calendar", text: "Personalized training plans")
                        FeaturePill(symbol: "heart.fill", text: "Garmin + HealthKit integration")
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

                    Text("By continuing you agree to our Terms of Service and Privacy Policy.")
                        .font(.caption2)
                        .foregroundStyle(Color.mutedText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.dark)
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
            try await session.signInWithApple(idToken: idToken, nonce: currentNonce)
        } catch let error as NSError
            where error.domain == ASAuthorizationError.errorDomain
               && error.code == ASAuthorizationError.canceled.rawValue {
            // User dismissed the sheet — not an error
        } catch {
            errorMessage = error.localizedDescription
        }
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
