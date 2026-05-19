import Foundation
import PostHog

protocol AnalyticsTracking {
    func track(_ event: String, properties: [String: Any])
    func identify(userId: String, traits: [String: Any])
    func reset()
}

final class PostHogAnalyticsService: AnalyticsTracking {
    func track(_ event: String, properties: [String: Any]) {
        PostHogSDK.shared.capture(event, properties: properties)
    }
    func identify(userId: String, traits: [String: Any]) {
        PostHogSDK.shared.identify(userId, userProperties: traits)
    }
    func reset() {
        PostHogSDK.shared.reset()
    }
}

final class NullAnalyticsService: AnalyticsTracking {
    func track(_ event: String, properties: [String: Any]) {}
    func identify(userId: String, traits: [String: Any]) {}
    func reset() {}
}

enum Analytics {
    static var shared: AnalyticsTracking = NullAnalyticsService()

    static func setup(projectToken: String, host: String) {
        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.flushAt = 20
        config.flushIntervalSeconds = 30
        config.personProfiles = .identifiedOnly
        PostHogSDK.shared.setup(config)
        shared = PostHogAnalyticsService()
    }
}
