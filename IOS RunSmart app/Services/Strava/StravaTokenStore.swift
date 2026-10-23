import Foundation
import Security

nonisolated protocol StravaTokenStoring: Sendable {
    func load() -> StravaTokens?
    func save(_ tokens: StravaTokens) throws
    func clear()
}

/// Strava tokens live in the Keychain, never in UserDefaults or the run store. They stay readable
/// after the first unlock so a finished run can upload while the phone is locked.
nonisolated struct KeychainStravaTokenStore: StravaTokenStoring {
    struct KeychainError: Error { let status: OSStatus }

    private let service = "com.runsmart.strava"
    private let account = "tokens"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func load() -> StravaTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder.strava.decode(StravaTokens.self, from: data)
    }

    func save(_ tokens: StravaTokens) throws {
        let data = try JSONEncoder.strava.encode(tokens)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// Whether stored tokens belong to the runner who is signed in now.
nonisolated enum StravaTokenOwnership {
    enum Verdict: Equatable {
        /// Issued to the signed-in runner.
        case owned
        /// Issued to someone else, or to nobody known (tokens saved before owners were recorded). Delete them.
        case foreign
        /// Nobody is signed in (guest, or the session is not loaded yet): do not use the tokens, but do not delete them.
        case unverifiable
    }

    static func verdict(tokenOwner: String?, currentUser: String?) -> Verdict {
        guard let tokenOwner, !tokenOwner.isEmpty else { return .foreign }
        guard let currentUser, !currentUser.isEmpty else { return .unverifiable }
        return tokenOwner.caseInsensitiveCompare(currentUser) == .orderedSame ? .owned : .foreign
    }
}

/// The Keychain outlives an uninstall, UserDefaults does not. A missing marker means this install has not run
/// yet, so any Strava item in the Keychain came from a previous install (maybe another person) and is deleted.
nonisolated struct StravaInstallGuard {
    static let markerKey = "runsmart.strava.installMarker"
    var defaults: UserDefaults = .standard

    func wipeKeychainIfFirstLaunch(_ store: StravaTokenStoring) {
        guard !defaults.bool(forKey: Self.markerKey) else { return }
        store.clear()
        defaults.set(true, forKey: Self.markerKey)
    }
}

/// For tests.
nonisolated final class InMemoryStravaTokenStore: StravaTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: StravaTokens?

    init(tokens: StravaTokens? = nil) { self.tokens = tokens }

    func load() -> StravaTokens? { lock.withLock { tokens } }
    func save(_ tokens: StravaTokens) throws { lock.withLock { self.tokens = tokens } }
    func clear() { lock.withLock { tokens = nil } }
}

nonisolated extension JSONEncoder {
    static var strava: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

nonisolated extension JSONDecoder {
    static var strava: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
