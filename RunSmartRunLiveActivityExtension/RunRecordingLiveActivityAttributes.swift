import ActivityKit
import Foundation

/// Mirror of the main-app attributes type (WP-38 S14b).
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
