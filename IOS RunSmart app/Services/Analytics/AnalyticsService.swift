import Foundation
import PostHog

protocol AnalyticsTracking {
    nonisolated func track(_ event: String, properties: [String: Any])
    nonisolated func identify(userId: String, traits: [String: Any])
    nonisolated func register(properties: [String: Any])
    nonisolated func reset()
}

nonisolated final class PostHogAnalyticsService: AnalyticsTracking {
    func track(_ event: String, properties: [String: Any]) {
        PostHogSDK.shared.capture(event, properties: Analytics.withPersonScope(properties))
    }
    func identify(userId: String, traits: [String: Any]) {
        PostHogSDK.shared.identify(userId, userProperties: traits)
    }
    func register(properties: [String: Any]) {
        PostHogSDK.shared.register(properties)
    }
    func reset() {
        PostHogSDK.shared.reset()
    }
}

nonisolated final class NullAnalyticsService: AnalyticsTracking {
    func track(_ event: String, properties: [String: Any]) {}
    func identify(userId: String, traits: [String: Any]) {}
    func register(properties: [String: Any]) {}
    func reset() {}
}

enum Analytics {
    static var shared: AnalyticsTracking = NullAnalyticsService()

    /// Build identity attached to every event as PostHog super properties.
    ///
    /// Measured 2026-07-20: `app_version` was present on 2 of 3,813 events over 60 days,
    /// so no RunSmart funnel could be split by build and no release-over-release
    /// comparison was possible.
    ///
    /// These are registered as super properties rather than merged inside
    /// ``PostHogAnalyticsService/track(_:properties:)`` on purpose. Two event sources
    /// never pass through that wrapper and would otherwise stay unlabelled:
    /// PostHog's autocaptured events (`Application Opened`, `Application Installed`,
    /// `$screen`) and the direct `PostHogSDK.shared.capture` calls in
    /// ``RunSmartAnalytics``. Registering on the SDK covers all three sources.
    ///
    /// `bundle` is injectable so the mapping is testable without a host app.
    static func buildIdentityProperties(bundle: Bundle = .main) -> [String: String] {
        var properties: [String: String] = [:]
        if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            properties["app_version"] = version
        }
        if let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !build.isEmpty {
            properties["app_build"] = build
        }
        return properties
    }

    static func setup(projectToken: String, host: String) {
#if DEBUG
        guard !RunSmartDemoMode.isEnabled else {
            shared = NullAnalyticsService()
            return
        }
#endif
        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.flushAt = 20
        config.flushIntervalSeconds = 30
        config.personProfiles = .identifiedOnly
        PostHogSDK.shared.setup(config)

        shared = PostHogAnalyticsService()
        registerBuildIdentity()
        registerInternalTester()
    }

    /// Restores release attribution after PostHog clears user and super-property
    /// state. This intentionally registers only build metadata, never identity.
    static func registerBuildIdentity(bundle: Bundle = .main) {
        let identity = buildIdentityProperties(bundle: bundle)
        guard !identity.isEmpty else { return }
        shared.register(properties: identity)
    }

    // MARK: - Internal tester (activation cliff plan, S5)

    static let internalTesterKey = "is_internal_tester"

    /// The value most recently handed to ``register(properties:)``.
    ///
    /// This is the single source of truth for both halves of the flag. The event
    /// property reaches PostHog as a super property; the person property reaches
    /// it as the `$set` block ``withPersonScope(_:)`` builds. Both read this one
    /// variable, so they cannot disagree on a payload the way they could if
    /// `$set` re-derived the value at send time. Resumely iOS PR #138 is the
    /// case: its `$set` re-read `UserDefaults` after `track` had already
    /// snapshotted the event property, so a sign-in landing in between made the
    /// two halves of the same event contradict each other.
    private(set) static var registeredInternalTester = false

    /// Publishes the internal-tester flag as a PostHog super property.
    ///
    /// Registered rather than merged inside
    /// ``PostHogAnalyticsService/track(_:properties:)`` for exactly the reason
    /// ``buildIdentityProperties(bundle:)`` is: autocaptured events
    /// (`Application Opened`, `Application Installed`, `$screen`) and the direct
    /// `PostHogSDK.shared.capture` calls in ``RunSmartAnalytics`` never pass
    /// through the wrapper. A merge there would leave those events unlabelled
    /// and the exclusion would leak on the very sessions it exists to catch.
    static func registerInternalTester(_ value: Bool = resolveInternalTester()) {
        registeredInternalTester = value
        shared.register(properties: [internalTesterKey: value ? "true" : "false"])
    }

    /// Adds the person-scoped `$set` block to an event's properties.
    ///
    /// The flag has to reach the *person*, not only the event. Resumely measured
    /// the difference on its own project over four months: `is_internal_tester`
    /// was true on 108 persons by event property and 3 by person property,
    /// because internal testers are per-build sweeps that rarely sign in — and
    /// every saved "clean" insight filters on the person property, so all of
    /// them were excluding 3 testers out of 108 (iOS PR #137).
    ///
    /// `$set` is placed in `properties` rather than passed as PostHog's
    /// `userProperties:` argument on purpose. `userProperties:` calls
    /// `requirePersonProcessing()`, which would create person profiles for
    /// anonymous users and quietly defeat `personProfiles = .identifiedOnly`.
    /// Going through `properties` leaves that setting intact, which also means
    /// the person half of this flag only lands for identified users; anonymous
    /// sessions carry the event property alone.
    ///
    /// The merge preserves any `$set` the caller already built —
    /// `trackOnboardingCompleted` sends `onboarding_completed_at` this way.
    static func withPersonScope(_ properties: [String: Any]) -> [String: Any] {
        var merged = properties
        var personProperties = properties["$set"] as? [String: Any] ?? [:]
        personProperties[internalTesterKey] = registeredInternalTester ? "true" : "false"
        merged["$set"] = personProperties
        return merged
    }

    /// Whether this install belongs to the team rather than to a real user.
    ///
    /// Every input is known at launch and recomputed identically on every launch,
    /// so nothing here needs persisting. The gap that leaves is a founder running
    /// a public **App Store** build without the launch argument: none of these
    /// signals fire, and that session still counts as a real user. Closing it
    /// needs a configured user-id allowlist, which needs Info.plist and xcconfig
    /// keys this app does not have yet.
    static func resolveInternalTester(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        receiptName: String? = Bundle.main.appStoreReceiptURL?.lastPathComponent
    ) -> Bool {
#if DEBUG
        return true
#else
        return resolveInternalTesterSignals(
            arguments: arguments,
            environment: environment,
            receiptName: receiptName
        )
#endif
    }

    /// The configuration-independent half of ``resolveInternalTester(arguments:environment:receiptName:)``,
    /// split out so the signals stay testable in a DEBUG test run.
    static func resolveInternalTesterSignals(
        arguments: [String],
        environment: [String: String],
        receiptName: String?
    ) -> Bool {
        if arguments.contains("--internal-tester") { return true }
        if environment["RUNSMART_INTERNAL_TESTER"] == "1" { return true }
        if receiptName == "sandboxReceipt" { return true }
        return false
    }
}
