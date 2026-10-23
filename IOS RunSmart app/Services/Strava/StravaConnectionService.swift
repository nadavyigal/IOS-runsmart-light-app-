import Foundation
import AuthenticationServices
import UIKit
import Combine
import Auth
import Supabase

/// Reads Strava's redirect back into the app. Pure so it can be tested.
nonisolated enum StravaCallback {
    /// The authorization code, or the reason there is none.
    static func code(from url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }

        if value("error") != nil { throw StravaError.cancelled }
        guard value("state") == expectedState else { throw StravaError.stateMismatch }
        let granted = (value("scope") ?? "").split(separator: ",").map { String($0) }
        guard granted.contains(StravaConfig.requiredScope) else { throw StravaError.missingScope }
        guard let code = value("code"), !code.isEmpty else { throw StravaError.malformedResponse }
        return code
    }
}

/// Opens Strava's sign-in page and returns the redirect. Replaced in tests.
@MainActor
protocol StravaAuthorizing {
    func authorize(url: URL, callbackScheme: String) async throws -> URL
}

@MainActor
final class WebAuthenticationStravaAuthorizer: NSObject, StravaAuthorizing, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: StravaError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? StravaError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: StravaError.cancelled)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

/// Owns the Strava connection: sign-in, Keychain tokens, refresh and disconnect.
@MainActor
final class StravaConnectionService: ObservableObject {
    static let shared = StravaConnectionService(installGuard: StravaInstallGuard())

    /// Nil when not connected.
    @Published private(set) var connectedAthleteName: String?
    @Published private(set) var isConnected: Bool
    @Published private(set) var isWorking = false
    @Published var lastMessage: String?

    private let tokenStore: StravaTokenStoring
    private let clientID: () -> String?
    private let supabaseAccessToken: () async -> String?
    /// The signed-in RunSmart user. Tokens are only used for the user they were issued to.
    private let currentUserID: () -> String?
    private let makeClient: () -> StravaClient
    private let authorizer: StravaAuthorizing
    private let now: () -> Date
    private var refreshTask: Task<StravaTokens, Error>?

    init(
        tokenStore: StravaTokenStoring = KeychainStravaTokenStore(),
        clientID: @escaping () -> String? = { StravaConfig.clientID },
        supabaseAccessToken: @escaping () async -> String? = {
            try? await SupabaseManager.client.auth.session.accessToken
        },
        currentUserID: @escaping () -> String? = {
            SupabaseManager.client.auth.currentUser?.id.uuidString
        },
        installGuard: StravaInstallGuard? = nil,
        makeClient: @escaping () -> StravaClient = {
            StravaClient(
                transport: URLSessionStravaTransport(),
                functionsBaseURL: SupabaseManager.functionsBaseURL,
                publishableKey: SupabaseManager.supabasePublishableKey
            )
        },
        authorizer: StravaAuthorizing? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.tokenStore = tokenStore
        self.clientID = clientID
        self.supabaseAccessToken = supabaseAccessToken
        self.currentUserID = currentUserID
        self.makeClient = makeClient
        self.authorizer = authorizer ?? WebAuthenticationStravaAuthorizer()
        self.now = now
        installGuard?.wipeKeychainIfFirstLaunch(tokenStore)
        isConnected = false
        reconcileOwnership()
    }

    /// Connected means: tokens exist and belong to the runner signed in now. Tokens that belong to someone
    /// else are deleted. With nobody signed in the tokens are kept but not used. Cheap, so callers run it
    /// before they read `isConnected`.
    func reconcileOwnership() {
        guard clientID() != nil, let tokens = tokenStore.load() else {
            isConnected = false
            connectedAthleteName = nil
            return
        }
        switch StravaTokenOwnership.verdict(tokenOwner: tokens.ownerUserID, currentUser: currentUserID()) {
        case .owned:
            apply(tokens)
        case .foreign:
            forgetTokens()
        case .unverifiable:
            isConnected = false
            connectedAthleteName = nil
        }
    }

    func availability(isSignedIn: Bool) -> StravaAvailability {
        StravaAvailability.resolve(clientID: clientID(), isSignedIn: isSignedIn)
    }

    // MARK: Connect and disconnect

    func connect() async {
        guard !isWorking else { return }
        guard let clientID = clientID() else { lastMessage = Self.message(for: StravaError.notConfigured); return }
        isWorking = true
        lastMessage = nil
        defer { isWorking = false }
        do {
            guard let supabaseToken = await supabaseAccessToken(), let owner = currentUserID() else { throw StravaError.notSignedIn }
            let state = UUID().uuidString
            let url = StravaConfig.authorizeURL(clientID: clientID, state: state)
            let callback = try await authorizer.authorize(url: url, callbackScheme: StravaConfig.callbackScheme)
            let code = try StravaCallback.code(from: callback, expectedState: state)
            var tokens = try await makeClient().tokens(.exchange(code: code), supabaseAccessToken: supabaseToken)
            tokens.ownerUserID = owner
            try tokenStore.save(tokens)
            apply(tokens)
        } catch StravaError.cancelled {
            // The runner closed the Strava page. Nothing to report.
        } catch {
            lastMessage = Self.message(for: error)
        }
    }

    func disconnect() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        if let tokens = tokenStore.load() {
            await makeClient().deauthorize(accessToken: tokens.accessToken)
        }
        forgetTokens()
    }

    /// Forgets the tokens on this device without calling Strava (sign out, account deletion).
    func forgetTokens() {
        refreshTask?.cancel()
        refreshTask = nil
        tokenStore.clear()
        isConnected = false
        connectedAthleteName = nil
        lastMessage = nil
    }

    // MARK: Access token

    /// A token that is good for the next few minutes, refreshed through the edge function when needed.
    func validAccessToken() async throws -> String {
        guard let tokens = tokenStore.load() else {
            forgetTokens()
            throw StravaError.notConnected
        }
        switch StravaTokenOwnership.verdict(tokenOwner: tokens.ownerUserID, currentUser: currentUserID()) {
        case .owned:
            break
        case .foreign:
            forgetTokens()
            throw StravaError.notConnected
        case .unverifiable:
            isConnected = false
            throw StravaError.notSignedIn
        }
        guard StravaTokenPolicy.needsRefresh(expiresAt: tokens.expiresAt, now: now()) else {
            return tokens.accessToken
        }
        if let refreshTask {
            return try await refreshTask.value.accessToken
        }
        let task = Task { [tokenStore, makeClient, supabaseAccessToken] () throws -> StravaTokens in
            guard let supabaseToken = await supabaseAccessToken() else { throw StravaError.notSignedIn }
            let fresh = try await makeClient().tokens(
                .refresh(refreshToken: tokens.refreshToken),
                supabaseAccessToken: supabaseToken,
                previous: tokens
            )
            try tokenStore.save(fresh)
            return fresh
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            apply(fresh)
            return fresh.accessToken
        } catch StravaError.invalidGrant {
            // Strava says the refresh token itself is no longer valid (access was revoked): ask the runner to
            // reconnect. Any other failure (Strava busy, offline, a server error) keeps the tokens for a later try.
            forgetTokens()
            lastMessage = "Strava access ended. Connect again to keep uploading."
            throw StravaError.notConnected
        }
    }

    private func apply(_ tokens: StravaTokens) {
        isConnected = true
        connectedAthleteName = tokens.athleteName
    }

    static func message(for error: Error) -> String {
        switch error as? StravaError {
        case .notConfigured: "Strava is not set up in this build."
        case .notSignedIn: "Sign in to RunSmart to connect Strava."
        case .missingScope: "RunSmart needs permission to upload activities. Connect again and keep that box ticked."
        case .stateMismatch, .malformedResponse: "Strava sent back something unexpected. Try again."
        case .unauthorized: "Your RunSmart session ended. Sign in again."
        case .rateLimited: "Strava is busy. Try again in a few minutes."
        case .rejected(let text): text
        default: "Could not reach Strava. Check your connection and try again."
        }
    }
}
