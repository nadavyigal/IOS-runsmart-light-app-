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
        PostHogSDK.shared.capture(event, properties: properties)
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
    }

    /// Restores release attribution after PostHog clears user and super-property
    /// state. This intentionally registers only build metadata, never identity.
    static func registerBuildIdentity(bundle: Bundle = .main) {
        let identity = buildIdentityProperties(bundle: bundle)
        guard !identity.isEmpty else { return }
        shared.register(properties: identity)
    }
}
