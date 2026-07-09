import ActivityKit
import Foundation

/// Shared Live Activity payload for an in-progress run (WP-38 S14b).
struct RunRecordingLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distanceLabel: String
        var movingTimeLabel: String
        var paceLabel: String
        var isPaused: Bool
    }

    var workoutTitle: String
}

extension Notification.Name {
    static let runSmartLiveActivityPauseResume = Notification.Name("RunSmartLiveActivityPauseResume")
    static let runSmartLiveActivityFinish = Notification.Name("RunSmartLiveActivityFinish")
}
