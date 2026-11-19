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
                    Text(RunLiveActivityFormat.distanceKm(context.state.distanceMeters))
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RunLiveActivityClock(state: context.state)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.isStale {
                        RunLiveActivityStaleNote()
                    } else {
                        RunRecordingLiveActivityControls(phase: context.state.phase)
                    }
                }
            } compactLeading: {
                Text(RunLiveActivityFormat.distanceKm(context.state.distanceMeters))
                    .font(.caption2.monospacedDigit())
            } compactTrailing: {
                Image(systemName: RunLiveActivitySymbol.name(for: context.state.phase))
            } minimal: {
                Image(systemName: RunLiveActivitySymbol.name(for: context.state.phase))
            }
        }
    }
}

enum RunLiveActivitySymbol {
    static func name(for phase: RunRecordingLiveActivityAttributes.Phase) -> String {
        switch phase {
        case .paused, .autoPaused: "pause.fill"
        case .finished: "checkmark"
        case .acquiring: "location.fill"
        case .running: "figure.run"
        }
    }
}

/// Moving time drawn by the system timer view, so the clock needs no Live Activity updates.
struct RunLiveActivityClock: View {
    let state: RunRecordingLiveActivityAttributes.ContentState

    var body: some View {
        Text(
            timerInterval: state.timerStart...Date.distantFuture,
            pauseTime: state.phase.isClockRunning ? nil : state.frozenClockEnd,
            countsDown: false,
            showsHours: true
        )
        .multilineTextAlignment(.trailing)
    }
}

private struct RunLiveActivityStaleNote: View {
    var body: some View {
        Label("Open RunSmart to update", systemImage: "arrow.clockwise")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
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
                Text(context.state.phase.statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 16) {
                metric(title: "Distance") {
                    Text(RunLiveActivityFormat.distanceKm(context.state.distanceMeters))
                }
                metric(title: "Moving time") {
                    RunLiveActivityClock(state: context.state)
                        .multilineTextAlignment(.leading)
                }
                metric(title: context.state.phase == .finished ? "Avg pace" : "Pace") {
                    Text(RunLiveActivityFormat.pace(
                        context.state.phase == .finished
                            ? context.state.averagePaceSecondsPerKm
                            : context.state.currentPaceSecondsPerKm
                    ))
                }
            }
            .opacity(context.isStale ? 0.55 : 1)

            if context.isStale {
                RunLiveActivityStaleNote()
            } else {
                RunRecordingLiveActivityControls(phase: context.state.phase)
            }
        }
        .padding(12)
    }

    private var statusColor: Color {
        switch context.state.phase {
        case .paused, .autoPaused: .orange
        case .acquiring: .blue
        case .running, .finished: .green
        }
    }

    private func metric<Value: View>(title: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            value()
                .font(.body.monospacedDigit())
        }
    }
}

private struct RunRecordingLiveActivityControls: View {
    var phase: RunRecordingLiveActivityAttributes.Phase

    var body: some View {
        if phase != .finished {
            HStack(spacing: 12) {
                Button(intent: PauseRunLiveActivityIntent()) {
                    Label(phase.isPausedLike ? "Resume" : "Pause", systemImage: phase.isPausedLike ? "play.fill" : "pause.fill")
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
}
