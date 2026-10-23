import Foundation

/// Strava setup. Everything Strava related stays hidden until `RUNSMART_STRAVA_CLIENT_ID` is set
/// in the gitignored RunSmartSecrets.xcconfig. The client secret never ships in the app: it lives
/// in the `strava_oauth` Supabase edge function.
nonisolated enum StravaConfig {
    static let infoPlistKey = "RUNSMART_STRAVA_CLIENT_ID"

    static let authorizeURL = URL(string: "https://www.strava.com/oauth/mobile/authorize")!
    static let apiBaseURL = URL(string: "https://www.strava.com/api/v3")!
    static let deauthorizeURL = URL(string: "https://www.strava.com/oauth/deauthorize")!

    /// Registered in Info.plist (CFBundleURLSchemes) for the existing deep links.
    static let callbackScheme = "runsmart"
    /// Register this redirect URI's host (`strava-callback`) as the Authorization Callback Domain in Strava.
    static let redirectURI = "runsmart://strava-callback"
    static let scope = "activity:write,read"
    /// Scope Strava must have granted for uploads to work.
    static let requiredScope = "activity:write"

    /// The client id from Info.plist, or nil when it is empty or still an unsubstituted `$(...)`.
    static func clientID(from info: [String: Any]?) -> String? {
        guard let raw = info?[infoPlistKey] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }

    static var clientID: String? {
        clientID(from: Bundle.main.infoDictionary)
    }

    static var isConfigured: Bool { clientID != nil }

    static func authorizeURL(clientID: String, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }
}

/// What the Strava UI shows. Pure so the gate can be tested without a view.
nonisolated enum StravaAvailability: Equatable {
    /// No client id in the build: no Strava row, no menu item, no setting.
    case hidden
    /// Configured, but there is no Supabase session for the token exchange (guest).
    case signInRequired
    case available

    static func resolve(clientID: String?, isSignedIn: Bool) -> StravaAvailability {
        guard let clientID, !clientID.isEmpty else { return .hidden }
        return isSignedIn ? .available : .signInRequired
    }
}

/// When a stored token needs a refresh. Strava access tokens last six hours.
nonisolated enum StravaTokenPolicy {
    static let refreshLeeway: TimeInterval = 5 * 60

    static func needsRefresh(expiresAt: Date, now: Date = Date()) -> Bool {
        expiresAt < now.addingTimeInterval(refreshLeeway)
    }
}
