import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ZStack {
            // ── Background ──────────────────────────────────────────────────
            Theme.bgPrimary.ignoresSafeArea()

            // Subtle top violet glow
            RadialGradient(
                colors: [Theme.accent.opacity(0.18), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // ── Hero ─────────────────────────────────────────────────
                    VStack(spacing: 16) {
                        // Brand mark
                        Image("ResumelyMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: Theme.accent.opacity(0.45), radius: 20, y: 8)

                        // Wordmark
                        Text("Resumely")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Theme.accent, Theme.accentBlue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Text("Your AI-powered resume edge.\nATS-optimized in seconds.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    .padding(.top, 60)
                    .padding(.bottom, 40)

                    // ── Sign in with Apple ───────────────────────────────────
                    SignInWithAppleButton(
                        viewModel.isSignUp ? .signUp : .signIn,
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { _ in }
                    )
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusButton, style: .continuous))
                    .onTapGesture {
                        Task { await viewModel.signInWithApple() }
                    }
                    .padding(.horizontal, 24)

                    // ── Divider ──────────────────────────────────────────────
                    HStack(spacing: 12) {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(Theme.textTertiary)
                        Text("or")
                            .font(.footnote)
                            .foregroundStyle(Theme.textTertiary)
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)

                    // ── Email form ───────────────────────────────────────────
                    VStack(spacing: 12) {
                        TextField("Email", text: $viewModel.email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .padding(14)
                            .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous)
                                    .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
                            )
                            .foregroundStyle(Theme.textPrimary)
                            .tint(Theme.accent)

                        SecureField("Password", text: $viewModel.password)
                            .textContentType(viewModel.isSignUp ? .newPassword : .password)
                            .padding(14)
                            .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.radiusBadge, style: .continuous)
                                    .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
                            )
                            .foregroundStyle(Theme.textPrimary)
                            .tint(Theme.accent)

                        // Primary CTA button
                        Button {
                            Task {
                                if viewModel.isSignUp {
                                    await viewModel.signUp()
                                } else {
                                    await viewModel.signInWithEmail()
                                }
                            }
                        } label: {
                            Group {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(viewModel.isSignUp ? "Create Account" : "Sign In")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(.white)
                            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton, style: .continuous))
                        }
                        .disabled(viewModel.isLoading)
                    }
                    .padding(.horizontal, 24)

                    // ── Toggle sign-in / sign-up ─────────────────────────────
                    Button {
                        withAnimation { viewModel.isSignUp.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.isSignUp ? "Already have an account?" : "Don't have an account?")
                                .foregroundStyle(Theme.textSecondary)
                            Text(viewModel.isSignUp ? "Sign In" : "Sign Up")
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.accentBlue)
                        }
                        .font(.footnote)
                    }
                    .padding(.top, 16)

                    // ── Error ────────────────────────────────────────────────
                    if let errorMessage = viewModel.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 24)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 40)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
    }
}
