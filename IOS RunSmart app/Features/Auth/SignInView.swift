import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject private var session: SupabaseSession
    @Environment(\.scenePhase) private var scenePhase
    /// Session-scoped, not view-scoped: SwiftUI rebuilds this view whenever the
    /// shell's auth state changes, and the wall events must stay once-per-session.
    private let wallTracker = SignInWallTracker.shared
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var currentNonce = AppleSignInHelper.randomNonce()
    @State private var legalDocument: LegalDocument?
    @State private var lastPresentedLegalDocument: LegalDocument?
    @State private var emailFlowCompleted = false
    /// Set on tap, cleared when Apple reports back or the app returns to the
    /// foreground. Guards against a second authorization being started while the
    /// first is still presenting; the foreground reset is the safety net so a
    /// missing callback can never leave the button permanently dead.
    @State private var isAwaitingAppleSheet = false
    /// Set synchronously the moment Apple reports back, before the deferred
    /// `Task` runs. Without it the foreground reset could re-arm the button
    /// while `handleAppleResult` is still awaiting the token exchange, and a
    /// second tap would regenerate `currentNonce` out from under the in-flight
    /// attempt — sending Supabase a nonce that does not match the credential.
    @State private var isHandlingAppleResult = false
    /// Presents the email path. Always reachable; emphasised once Apple has
    /// actually failed for this user.
    @State private var isShowingEmailSignIn = false
    /// Set when Apple returns a real failure (not a cancel). A missing or
    /// restricted Apple Account is one reproducible cause of a bare code 1000,
    /// so once Apple has failed the alternative stops being a secondary option
    /// and becomes the recommendation.
    @State private var appleSignInHasFailed = false

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
                            // The request closure runs on tap, before Apple's sheet
                            // appears — so this records the attempt even when the
                            // system sheet itself is what fails.
                            wallTracker.signInTapped()
                            isAwaitingAppleSheet = true
                            // Fresh nonce per attempt — store raw, send hashed to Apple
                            currentNonce = AppleSignInHelper.randomNonce()
                            request.requestedScopes = [.fullName, .email]
                            request.nonce = AppleSignInHelper.sha256(currentNonce)
                        } onCompletion: { result in
                            // Claim the attempt synchronously, before the Task
                            // suspends, so the foreground reset below cannot
                            // re-arm the button while this result is in flight.
                            isHandlingAppleResult = true
                            // Use the credential Apple just gave us — do NOT create a second
                            // ASAuthorizationController; that is what caused the concurrency warning.
                            Task { @MainActor in await handleAppleResult(result) }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        // Apple's sheet takes a moment to appear and nothing on
                        // screen changes meanwhile, so a user who sees no response
                        // taps again — observed in the 2026-07-22 device session,
                        // which logged two taps 12s apart before one completion.
                        // A second tap starts a second authorization against the
                        // same view, so suppress it rather than let two run.
                        //
                        // Hit-testing is disabled instead of swapping the button
                        // for a spinner on purpose: replacing it would unmount the
                        // view that Apple is presenting from, mid-authorization.
                        .allowsHitTesting(!isAwaitingAppleSheet)
                        .opacity(isAwaitingAppleSheet ? 0.6 : 1)

                        emailAlternative
                    }

                    VStack(spacing: 4) {
                        Text("By continuing you agree to our")
                            .foregroundStyle(Color.mutedText)

                        HStack(spacing: 4) {
                            Button("Terms of Service") { presentLegalDocument(.terms) }
                            Text("and")
                                .foregroundStyle(Color.mutedText)
                            Button("Privacy Policy") { presentLegalDocument(.privacy) }
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
        .onAppear { wallTracker.wallAppeared() }
        .onChange(of: scenePhase) { _, phase in
            // Returning to the foreground re-arms the button, but only when no
            // result is being processed — otherwise this races the deferred
            // completion Task and can hand a second tap the chance to replace
            // `currentNonce` mid-exchange. With a result in flight the defer in
            // `handleAppleResult` is what clears the guard. This stays the
            // fallback for the one case nothing else covers: a sheet dismissed
            // without ever calling back, which would leave the wall a dead end.
            if phase == .active, !isHandlingAppleResult {
                isAwaitingAppleSheet = false
            }
            switch phase {
            case .active:
                wallTracker.appBecameActive()
            case .inactive:
                wallTracker.appBecameInactive()
            case .background:
                // `.background` is the last phase the app reliably observes
                // before termination, so it also doubles as the abandon signal.
                wallTracker.appDidEnterBackground()
            @unknown default:
                break
            }
        }
        .onChange(of: session.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated, isShowingEmailSignIn {
                emailFlowCompleted = true
            }
        }
        .sheet(item: $legalDocument, onDismiss: {
            guard let document = lastPresentedLegalDocument else { return }
            Analytics.trackPreAuthScreenDismissed(document.preAuthScreen)
            lastPresentedLegalDocument = nil
        }) { document in
            SafariView(url: document.url)
                .ignoresSafeArea()
                .onAppear {
                    Analytics.trackPreAuthScreenViewed(document.preAuthScreen)
                }
        }
        .sheet(isPresented: $isShowingEmailSignIn, onDismiss: {
            if !emailFlowCompleted {
                Analytics.trackPreAuthScreenDismissed(.emailSignIn)
            }
            emailFlowCompleted = false
        }) {
            EmailSignInView(model: EmailSignInModel(gateway: .init(
                signIn: { email, password in
                    try await session.signInWithEmail(email: email, password: password)
                },
                signUp: { email, password in
                    try await session.signUpWithEmail(email: email, password: password)
                }
            )))
        }
    }

    /// The non-Apple way in. Present at all times so no user is ever cornered,
    /// and promoted to a filled button with an explanatory line once Apple has
    /// failed — at that point it is the only thing left that can work.
    @ViewBuilder
    private var emailAlternative: some View {
        VStack(spacing: 8) {
            if appleSignInHasFailed {
                Text("Can't use Sign in with Apple? Use your email instead.")
                    .font(.caption)
                    .foregroundStyle(Color.mutedText)
                    .multilineTextAlignment(.center)
            }

            Button {
                Analytics.trackSignInMethodSelected(method: "email")
                emailFlowCompleted = false
                isShowingEmailSignIn = true
            } label: {
                Text("Continue with email")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .foregroundStyle(appleSignInHasFailed ? .black : .white)
            .background {
                if appleSignInHasFailed {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.lime)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.hairline, lineWidth: 0.5)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @MainActor
    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        isSigningIn = true
        errorMessage = nil
        defer {
            isSigningIn = false
            isAwaitingAppleSheet = false
            isHandlingAppleResult = false
        }

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
            appleSignInHasFailed = true
            Analytics.trackSignInFailed(error: error, method: "apple")
        }
    }

    /// Maps Apple sign-in failures to user-facing copy. Never forwards
    /// `NSError.localizedDescription` — that surfaces raw strings like
    /// "com.apple.AuthenticationServices.AuthorizationError error 1000" to a
    /// first-time user. `.canceled` returns nil (user backed out silently).
    ///
    /// The copy names iCloud deliberately, and now also names the way out.
    ///
    /// Reproduced on a clean simulator 2026-07-26: with no Apple Account signed
    /// in, iOS shows its own "Sign in to your Apple Account" alert and, once
    /// dismissed, returns a bare `ASAuthorizationError` code 1000 with no
    /// underlying error — the same signature seen in the failing production
    /// sessions. Apple's `.unknown` code is not diagnostic by itself, so this
    /// does not prove every production failure had that cause. It does prove
    /// that retry-only copy can strand some users, which is why the copy points
    /// at the independent email path.
    static func humanReadableAppleSignInError(for error: Error) -> String? {
        let nsError = error as NSError
        guard nsError.domain == ASAuthorizationError.errorDomain else {
            // Not Apple's failure. `handleAppleResult` catches everything,
            // including Supabase and URL-loading errors from the token
            // exchange, and those have nothing to do with iCloud — sending
            // such a user to Settings wastes the one retry they will give us.
            return "Sign-in didn't finish and nothing was created. Please tap to try again."
        }
        if nsError.code == ASAuthorizationError.canceled.rawValue {
            return nil
        }
        return "Apple sign-in didn't finish and nothing was created. "
             + "Check that you're signed in to iCloud in Settings, "
             + "or continue with your email below."
    }

    private func appleDisplayName(from fullName: PersonNameComponents?) -> String? {
        guard let fullName else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .medium
        let name = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func presentLegalDocument(_ document: LegalDocument) {
        lastPresentedLegalDocument = document
        legalDocument = document
    }
}

private extension SignInView.LegalDocument {
    var preAuthScreen: PreAuthScreen {
        switch self {
        case .terms: .terms
        case .privacy: .privacy
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
