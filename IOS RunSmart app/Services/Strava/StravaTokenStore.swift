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
