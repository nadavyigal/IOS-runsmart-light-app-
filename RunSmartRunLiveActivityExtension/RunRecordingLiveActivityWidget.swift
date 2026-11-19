import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// One Live Activity whose layout follows the run's data (founder decision 2026-11-19):
// - target pace set (planned or coach-set workout): Direction B, pace vs target, plus a
//   distance ring when the goal distance is known;
// - free run or no target: Direction A, time and distance large, pace secondary.
// Motion is limited to system transitions (one pop on a km split). Nothing loops.

private typealias LAState = RunRecordingLiveActivityAttributes.ContentState
private typealias LAPhase = RunRecordingLiveActivityAttributes.Phase

private enum LAColor {
    static let lime = Color(red: 0.800, green: 1.000, blue: 0.000)
    static let orange = Color(red: 0.984, green: 0.573, blue: 0.235)
    static let green = Color(red: 0.176, green: 0.863, blue: 0.510)
    static let blue = Color(red: 0.376, green: 0.647, blue: 0.980)
    static let muted = Color.white.opacity(0.62)

    static func phase(_ phase: LAPhase) -> Color {
        switch phase {
        case .running: lime
        case .paused, .autoPaused: orange
        case .acquiring: blue
        case .finished: green
        }
    }

    static func standing(_ standing: RunLiveActivityPaceTarget.Standing) -> Color {
        switch standing {
        case .onTarget, .fast: green
        case .slow: orange
        case .unknown: muted
        }
    }
}

/// Which layout a run gets, from its attributes only, so it never flips mid-run.
private struct LALayout {
    let target: Int?
    let goalMeters: Double?

    init(_ attributes: RunRecordingLiveActivityAttributes) {
        target = attributes.targetPaceSecondsPerKm.flatMap { $0 > 0 ? $0 : nil }
        goalMeters = attributes.goalDistanceMeters.flatMap { $0 > 0 ? $0 : nil }
    }

    var isPaceFirst: Bool { target != nil }

    func progress(_ state: LAState) -> Double? {
        guard let goalMeters else { return nil }
        return state.phase == .finished ? 1 : min(1, max(0, state.distanceMeters / goalMeters))
    }

    static func goalLabel(_ meters: Double) -> String {
        let km = meters / 1_000
        return km.rounded() == km ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
    }
}

struct RunRecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunRecordingLiveActivityAttributes.self) { context in
            RunLiveActivityLockView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(LAColor.lime)
                .widgetURL(context.state.phase == .finished ? RunSmartRunDeepLink.debrief : RunSmartRunDeepLink.live)
        } dynamicIsland: { context in
            let layout = LALayout(context.attributes)
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeading(layout: layout, state: state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailing(layout: layout, state: state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(layout: layout, state: state, isStale: context.isStale)
                }
            } compactLeading: {
                CompactLeading(layout: layout, state: state)
            } compactTrailing: {
                CompactTrailing(layout: layout, state: state)
            } minimal: {
                MinimalView(layout: layout, state: state)
            }
            .widgetURL(state.phase == .finished ? RunSmartRunDeepLink.debrief : RunSmartRunDeepLink.live)
            .keylineTint(LAColor.phase(state.phase))
        }
    }
}

// MARK: - Shared pieces

/// Moving time drawn by the system timer view, so the clock needs no Live Activity updates.
private struct RunClock: View {
    let state: LAState

    var body: some View {
        Text(
            timerInterval: state.timerStart...Date.distantFuture,
            pauseTime: state.phase.isClockRunning ? nil : state.frozenClockEnd,
            countsDown: false,
            showsHours: true
        )
        .monospacedDigit()
    }
}

private struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct PhaseSymbol: View {
    let phase: LAPhase

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(LAColor.phase(phase))
    }

    private var symbol: String {
        switch phase {
        case .paused, .autoPaused: "pause.fill"
        case .finished: "checkmark"
        case .acquiring: "location.fill"
        case .running: "figure.run"
        }
    }
}

private struct SplitChip: View {
    let state: LAState

    var body: some View {
        if let km = state.lastSplitKilometer, let until = state.splitHighlightUntil, until > Date() {
            Text("Km \(km) · \(RunLiveActivityFormat.pace(state.lastSplitPaceSecondsPerKm)) /km")
                .font(.caption.weight(.bold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(LAColor.lime.opacity(0.16), in: Capsule())
                .foregroundStyle(LAColor.lime)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }
}

private struct StatusChip: View {
    let phase: LAPhase

    var body: some View {
        Text(phase.statusLabel.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(LAColor.phase(phase))
    }
}

private struct Metric<Value: View>: View {
    let title: String
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LAColor.muted)
            value
        }
    }
}

private struct DistanceText: View {
    let meters: Double
    var font: Font = .system(size: 30, weight: .bold)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(RunLiveActivityFormat.distanceKm(meters))
                .font(font.monospacedDigit())
            Text("km")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LAColor.muted)
        }
    }
}

/// Pace against the target window, with a marker for the current pace.
private struct PaceTargetBar: View {
    let pace: Int?
    let target: Int

    var body: some View {
        let standing = RunLiveActivityPaceTarget.standing(pace: pace, target: target)
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let span = Double(RunLiveActivityPaceTarget.band * 4)
                let low = Double(target) - span / 2
                let windowStart = (Double(target - RunLiveActivityPaceTarget.band) - low) / span
                let windowWidth = Double(RunLiveActivityPaceTarget.band * 2) / span
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(LAColor.green.opacity(0.45))
                        .frame(width: width * windowWidth)
                        .offset(x: width * windowStart)
                    if let pace {
                        let position = min(1, max(0, (Double(pace) - low) / span))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white)
                            .frame(width: 4, height: 14)
                            .offset(x: width * position - 2)
                    }
                }
            }
            .frame(height: 8)
            HStack {
                Text(RunLiveActivityPaceTarget.rangeLabel(target: target))
                    .foregroundStyle(LAColor.muted)
                Spacer(minLength: 6)
                Text(RunLiveActivityPaceTarget.deltaLabel(pace: pace, target: target) ?? "Pace shows once moving")
                    .foregroundStyle(LAColor.standing(standing))
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .lineLimit(1)
        }
    }
}

private struct StaleNote: View {
    var body: some View {
        Label("Open RunSmart to update", systemImage: "arrow.clockwise")
            .font(.caption.weight(.semibold))
            .foregroundStyle(LAColor.muted)
    }
}

private struct Controls: View {
    let phase: LAPhase
    var compactFinish = false

    var body: some View {
        if phase == .finished {
            Label("View debrief", systemImage: "chevron.right")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LAColor.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                Button(intent: PauseRunLiveActivityIntent()) {
                    Label(phase.isPausedLike ? "Resume" : "Pause", systemImage: phase.isPausedLike ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(phase.isPausedLike ? LAColor.orange : LAColor.lime)
                .foregroundStyle(Color.black)

                Button(intent: FinishRunLiveActivityIntent()) {
                    Label("Finish", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: compactFinish ? 90 : .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
    }
}

// MARK: - Lock Screen

private struct RunLiveActivityLockView: View {
    let attributes: RunRecordingLiveActivityAttributes
    let state: LAState
    let isStale: Bool

    private var layout: LALayout { LALayout(attributes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Group {
                if layout.isPaceFirst, state.phase != .acquiring {
                    paceFirstBody
                } else {
                    runFirstBody
                }
            }
            .opacity(isStale ? 0.55 : 1)
            if isStale {
                StaleNote()
            } else {
                Controls(phase: state.phase, compactFinish: layout.isPaceFirst)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .foregroundStyle(Color.white)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "figure.run")
                .foregroundStyle(LAColor.phase(state.phase))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 6)
            StatusChip(phase: state.phase)
        }
    }

    private var title: String {
        guard let target = layout.target else { return attributes.workoutTitle }
        let goal = layout.goalMeters.map { " · " + LALayout.goalLabel($0) } ?? ""
        return attributes.workoutTitle + goal + " @ " + RunLiveActivityFormat.pace(target)
    }

    /// Direction A: time and distance large, pace secondary.
    private var runFirstBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom) {
                Metric(title: "Time") {
                    RunClock(state: state)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(LAColor.phase(state.phase))
                }
                Spacer()
                Metric(title: "Distance", alignment: .trailing) {
                    DistanceText(meters: state.distanceMeters)
                }
            }
            HStack {
                Text(secondaryLine)
                    .font(.footnote.weight(.medium).monospacedDigit())
                    .foregroundStyle(LAColor.muted)
                    .lineLimit(1)
                Spacer(minLength: 6)
                SplitChip(state: state)
            }
        }
    }

    private var secondaryLine: String {
        switch state.phase {
        case .acquiring:
            return state.gpsAccuracyMeters.map { "GPS ±\($0) m · distance resumes with a good signal" } ?? "Waiting for GPS"
        case .finished:
            return "Avg pace \(RunLiveActivityFormat.pace(state.averagePaceSecondsPerKm)) /km"
        case .paused, .autoPaused:
            return "\(state.phase.statusLabel) at \(RunLiveActivityFormat.distanceKm(state.distanceMeters)) km"
        case .running:
            return "Pace \(RunLiveActivityFormat.pace(state.currentPaceSecondsPerKm)) · Avg \(RunLiveActivityFormat.pace(state.averagePaceSecondsPerKm)) /km"
        }
    }

    /// Direction B: pace against target, distance ring or bar toward the goal when known.
    private var paceFirstBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if let goal = layout.goalMeters {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(RunLiveActivityFormat.distanceKm(state.distanceMeters))
                            .font(.system(size: 24, weight: .bold).monospacedDigit())
                        Text("of \(LALayout.goalLabel(goal))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LAColor.muted)
                    }
                } else {
                    DistanceText(meters: state.distanceMeters, font: .system(size: 24, weight: .bold))
                }
                Spacer(minLength: 8)
                // The timer view claims its widest width; pin it so it sits on the right edge.
                RunClock(state: state)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(LAColor.phase(state.phase))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 104, alignment: .trailing)
            }
            if let progress = layout.progress(state) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(LAColor.phase(state.phase))
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 6)
            }
            if state.phase == .finished {
                Text("Avg pace \(RunLiveActivityFormat.pace(state.averagePaceSecondsPerKm)) /km · target \(RunLiveActivityFormat.pace(layout.target))")
                    .font(.footnote.weight(.medium).monospacedDigit())
                    .foregroundStyle(LAColor.muted)
            } else if state.phase.isPausedLike {
                Text(state.phase.statusLabel)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(LAColor.orange)
            } else if let target = layout.target {
                PaceTargetBar(pace: state.currentPaceSecondsPerKm, target: target)
            }
            SplitChip(state: state)
        }
    }
}

// MARK: - Dynamic Island

private struct CompactLeading: View {
    let layout: LALayout
    let state: LAState

    var body: some View {
        if state.phase == .acquiring || state.phase == .finished {
            PhaseSymbol(phase: state.phase)
        } else if layout.isPaceFirst, let progress = layout.progress(state) {
            ProgressRing(progress: progress, color: LAColor.phase(state.phase), lineWidth: 3)
                .frame(width: 20, height: 20)
        } else {
            RunClock(state: state)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LAColor.phase(state.phase))
                .frame(maxWidth: 46)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct CompactTrailing: View {
    let layout: LALayout
    let state: LAState

    var body: some View {
        if state.phase == .acquiring {
            Text("GPS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LAColor.muted)
        } else if layout.isPaceFirst, state.phase == .running {
            Text(RunLiveActivityFormat.pace(state.currentPaceSecondsPerKm))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(LAColor.standing(RunLiveActivityPaceTarget.standing(pace: state.currentPaceSecondsPerKm, target: layout.target)))
        } else if state.phase.isPausedLike, layout.isPaceFirst {
            PhaseSymbol(phase: state.phase)
        } else {
            Text(RunLiveActivityFormat.distanceKm(state.distanceMeters))
                .font(.caption.weight(.semibold).monospacedDigit())
                .minimumScaleFactor(0.8)
        }
    }
}

private struct MinimalView: View {
    let layout: LALayout
    let state: LAState

    var body: some View {
        if state.phase == .acquiring || state.phase == .finished || state.phase.isPausedLike {
            PhaseSymbol(phase: state.phase)
        } else if let progress = layout.progress(state) {
            // B's ring, only when the goal distance is known. Never an empty ring.
            ProgressRing(progress: progress, color: LAColor.lime, lineWidth: 2.5)
                .overlay(
                    Text("\(Int(state.distanceMeters / 1_000))")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                )
                .frame(width: 22, height: 22)
        } else {
            Text(String(format: "%.1f", state.distanceMeters / 1_000))
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(LAColor.lime)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct ExpandedLeading: View {
    let layout: LALayout
    let state: LAState

    var body: some View {
        if layout.isPaceFirst, state.phase != .acquiring {
            HStack(spacing: 6) {
                if let progress = layout.progress(state) {
                    ProgressRing(progress: progress, color: LAColor.phase(state.phase), lineWidth: 4)
                        .overlay(
                            Text(String(format: "%.1f", state.distanceMeters / 1_000))
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                        )
                        .frame(width: 40, height: 40)
                    if let goal = layout.goalMeters {
                        Text("of \(LALayout.goalLabel(goal))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(LAColor.muted)
                    }
                } else {
                    Metric(title: "Distance") { DistanceText(meters: state.distanceMeters, font: .title3.weight(.bold)) }
                }
            }
            .padding(.leading, 10)
        } else {
            Metric(title: "Time") {
                RunClock(state: state)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(LAColor.phase(state.phase))
            }
            .padding(.leading, 10)
        }
    }
}

private struct ExpandedTrailing: View {
    let layout: LALayout
    let state: LAState

    var body: some View {
        Group {
            if state.phase == .acquiring {
                Metric(title: "GPS", alignment: .trailing) {
                    Text(state.gpsAccuracyMeters.map { "±\($0) m" } ?? "--")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(LAColor.blue)
                }
            } else if layout.isPaceFirst {
                Metric(title: state.phase == .finished ? "Avg pace" : "Pace", alignment: .trailing) {
                    let pace = state.phase == .finished ? state.averagePaceSecondsPerKm : state.currentPaceSecondsPerKm
                    Text(RunLiveActivityFormat.pace(pace))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(state.phase == .finished ? LAColor.green : LAColor.standing(RunLiveActivityPaceTarget.standing(pace: pace, target: layout.target)))
                }
            } else {
                Metric(title: "Distance", alignment: .trailing) {
                    DistanceText(meters: state.distanceMeters, font: .title2.weight(.bold))
                }
            }
        }
        .padding(.trailing, 10)
    }
}

private struct ExpandedBottom: View {
    let layout: LALayout
    let state: LAState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 8) {
            if isStale {
                StaleNote()
            } else {
                HStack {
                    detail
                    Spacer(minLength: 4)
                    SplitChip(state: state)
                }
                Controls(phase: state.phase, compactFinish: layout.isPaceFirst)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var detail: some View {
        if state.phase == .finished {
            Text("Finished · avg \(RunLiveActivityFormat.pace(state.averagePaceSecondsPerKm)) /km")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(LAColor.muted)
        } else if state.phase.isPausedLike {
            Text(state.phase.statusLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(LAColor.orange)
        } else if state.phase == .acquiring {
            Text("Finding GPS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LAColor.blue)
        } else if layout.isPaceFirst, let target = layout.target {
            PaceTargetBar(pace: state.currentPaceSecondsPerKm, target: target)
        } else {
            Text("Pace \(RunLiveActivityFormat.pace(state.currentPaceSecondsPerKm)) /km · avg \(RunLiveActivityFormat.pace(state.averagePaceSecondsPerKm))")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(LAColor.muted)
        }
    }
}

// MARK: - Previews

#if DEBUG
private enum LAPreview {
    static let start = Date().addingTimeInterval(-1_453)
    static let freeRun = RunRecordingLiveActivityAttributes(runStartedAt: start, workoutTitle: "Free Run")
    static let tempo = RunRecordingLiveActivityAttributes(runStartedAt: start, workoutTitle: "Tempo run", goalDistanceMeters: 8_000, targetPaceSecondsPerKm: 330)
    static let targetNoGoal = RunRecordingLiveActivityAttributes(runStartedAt: start, workoutTitle: "Steady 40 min", targetPaceSecondsPerKm: 345)

    static func state(_ phase: LAPhase, distance: Double = 4_570, pace: Int? = 318, split: Bool = false) -> LAState {
        LAState(
            phase: phase,
            timerStart: Date().addingTimeInterval(-1_453),
            movingSeconds: 1_453,
            distanceMeters: distance,
            currentPaceSecondsPerKm: phase == .running ? pace : nil,
            averagePaceSecondsPerKm: 318,
            lastSplitKilometer: split ? 4 : nil,
            lastSplitPaceSecondsPerKm: split ? 316 : nil,
            gpsAccuracyMeters: phase == .acquiring ? 48 : nil,
            splitHighlightUntil: split ? Date().addingTimeInterval(30) : nil
        )
    }
}

#Preview("Free run · Lock Screen", as: .content, using: LAPreview.freeRun) {
    RunRecordingLiveActivityWidget()
} contentStates: {
    LAPreview.state(.running)
    LAPreview.state(.running, split: true)
    LAPreview.state(.acquiring, pace: nil)
    LAPreview.state(.paused)
    LAPreview.state(.autoPaused)
    LAPreview.state(.finished, distance: 8_020)
}

#Preview("Target pace · Lock Screen", as: .content, using: LAPreview.tempo) {
    RunRecordingLiveActivityWidget()
} contentStates: {
    LAPreview.state(.running)
    LAPreview.state(.running, split: true)
    LAPreview.state(.acquiring, pace: nil)
    LAPreview.state(.paused)
    LAPreview.state(.autoPaused)
    LAPreview.state(.finished, distance: 8_020)
}

#Preview("Target, no goal · Lock Screen", as: .content, using: LAPreview.targetNoGoal) {
    RunRecordingLiveActivityWidget()
} contentStates: {
    LAPreview.state(.running)
    LAPreview.state(.running, split: true)
    LAPreview.state(.acquiring, pace: nil)
    LAPreview.state(.paused)
    LAPreview.state(.autoPaused)
    LAPreview.state(.finished, distance: 8_020)
}

#Preview("Free run · expanded", as: .dynamicIsland(.expanded), using: LAPreview.freeRun) {
    RunRecordingLiveActivityWidget()
} contentStates: {
    LAPreview.state(.running)
    LAPreview.state(.running, split: true)
    LAPreview.state(.acquiring, pace: nil)
    LAPreview.state(.paused)
    LAPreview.state(.autoPaused)
    LAPreview.state(.finished, distance: 8_020)
}

#Preview("Target pace · expanded", as: .dynamicIsland(.expanded), using: LAPreview.tempo) {
    RunRecordingLiveActivityWidget()
} contentStates: {
    LAPreview.state(.running)
    LAPreview.state(.running, split: true)
    LAPreview.state(.acquiring, pace: nil)
    LAPreview.state(.paused)
    LAPreview.state(.autoPaused)
    LAPreview.state(.finished, distance: 8_020)
}

#Preview("Target pace · compact", as: .dynamicIsland(.compact), using: LAPreview.tempo) {
    RunRecordingLiveActivityWidget()
} contentStates: {
    LAPreview.state(.running)
    LAPreview.state(.running, split: true)
    LAPreview.state(.acquiring, pace: nil)
    LAPreview.state(.paused)
    LAPreview.state(.autoPaused)
    LAPreview.state(.finished, distance: 8_020)
}

#Preview("Free run · compact", as: .dynamicIsland(.compact), using: LAPreview.freeRun) {
    RunRecordingLiveActivityWidget()
} contentStates: {
    LAPreview.state(.running)
    LAPreview.state(.running, split: true)
    LAPreview.state(.acquiring, pace: nil)
    LAPreview.state(.paused)
    LAPreview.state(.autoPaused)
    LAPreview.state(.finished, distance: 8_020)
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: LAPreview.tempo) {
    RunRecordingLiveActivityWidget()
} contentStates: {
    LAPreview.state(.running)
    LAPreview.state(.running, split: true)
    LAPreview.state(.acquiring, pace: nil)
    LAPreview.state(.paused)
    LAPreview.state(.autoPaused)
    LAPreview.state(.finished, distance: 8_020)
}
#endif
