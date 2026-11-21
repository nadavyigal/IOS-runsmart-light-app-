import Foundation

/// Typed analytics for Coach Experience v2 (refined plan S3, v1.3 §3.8).
///
/// C7.0 ships this with no events. Each later story adds its own cases from v1.3 §3.8
/// in the PR that fires them, so events are reviewed with the code that sends them.
///
/// Property rules (v1.3 §3.8): only internal uuids, enums, counts and durations.
/// Never names, note, flag or reply text, or RPE values tied to a person. Use
/// `CoachV2Analytics.Value` so a free-text property cannot compile.
nonisolated enum CoachV2Analytics {
    /// The only property values an event may carry.
    enum Value: Equatable, Sendable {
        case id(UUID)
        case count(Int)
        case seconds(Int)
        case flag(Bool)
        /// A fixed enum case from code, never user text.
        case kind(String)

        var raw: Any {
            switch self {
            case .id(let id): id.uuidString.lowercased()
            case .count(let value): value
            case .seconds(let value): value
            case .flag(let value): value
            case .kind(let value): value
            }
        }
    }

    /// One case per event. Empty until a story adds the first one.
    enum Event: Sendable {
        var name: String {
            switch self {}
        }

        var properties: [String: Value] {
            switch self {}
        }
    }

    /// Sends one event through the app's analytics path (PostHog via `Analytics.shared`).
    @MainActor
    static func track(_ event: Event, to tracker: any AnalyticsTracking = Analytics.shared) {
        tracker.track(event.name, properties: event.properties.mapValues(\.raw))
    }
}
