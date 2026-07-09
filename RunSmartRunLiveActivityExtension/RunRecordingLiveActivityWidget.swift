import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct RunRecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunRecordingLiveActivityAttributes.self) { context in
            RunRecordingLiveActivityLockView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.distanceLabel)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.movingTimeLabel)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RunRecordingLiveActivityControls(isPaused: context.state.isPaused)
                }
            } compactLeading: {
                Text(context.state.distanceLabel)
                    .font(.caption2.monospacedDigit())
            } compactTrailing: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
            } minimal: {
                Image(systemName: "figure.run")
            }
        }
    }
}

private struct RunRecordingLiveActivityLockView: View {
    let context: ActivityViewContext<RunRecordingLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(context.attributes.workoutTitle)
                    .font(.headline)
                Spacer()
                Text(context.state.isPaused ? "Paused" : "Recording")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(context.state.isPaused ? .orange : .green)
            }

            HStack(spacing: 16) {
                metric(title: "Distance", value: context.state.distanceLabel)
                metric(title: "Moving time", value: context.state.movingTimeLabel)
                metric(title: "Pace", value: context.state.paceLabel)
            }

            RunRecordingLiveActivityControls(isPaused: context.state.isPaused)
        }
        .padding(12)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
        }
    }
}

private struct RunRecordingLiveActivityControls: View {
    var isPaused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(intent: PauseRunLiveActivityIntent()) {
                Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button(intent: FinishRunLiveActivityIntent()) {
                Label("Finish", systemImage: "stop.fill")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }
}
