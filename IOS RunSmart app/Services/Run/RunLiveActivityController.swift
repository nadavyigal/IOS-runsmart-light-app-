import ActivityKit
import Foundation

/// Starts, updates, and ends the run-recording Live Activity (WP-38 S14b).
@MainActor
enum RunLiveActivityController {
    private static var activity: Activity<RunRecordingLiveActivityAttributes>?

    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func sync(
        workoutTitle: String,
        distanceLabel: String,
        movingTimeLabel: String,
        paceLabel: String,
        isPaused: Bool,
        isActive: Bool
    ) {
        guard isSupported else {
            end()
            return
        }

        guard isActive else {
            end()
            return
        }

        let state = RunRecordingLiveActivityAttributes.ContentState(
            distanceLabel: distanceLabel,
            movingTimeLabel: movingTimeLabel,
            paceLabel: paceLabel,
            isPaused: isPaused
        )

        if let activity {
            Task {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
            return
        }

        let attributes = RunRecordingLiveActivityAttributes(workoutTitle: workoutTitle)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
#if DEBUG
            print("RunLiveActivityController: Activity.request failed: \(error)")
#endif
            activity = nil
        }
    }

    static func end() {
        guard let activity else { return }
        let current = activity.content.state
        Task {
            await activity.end(
                ActivityContent(state: current, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        self.activity = nil
    }
}
