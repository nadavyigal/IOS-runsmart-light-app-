import SwiftUI
import WidgetKit

/// Small home-screen widget (founder decision 2026-11-19): this week's km against the plan's
/// week goal as a ring, and "Run in progress" while a run is live. Reads only the App Group
/// snapshot the app writes; never calls the network.
struct RunSmartWeeklyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RunSmartWidgetSnapshotStore.widgetKind, provider: RunSmartWeeklyProvider()) { entry in
            RunSmartWeeklyWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(red: 0.063, green: 0.071, blue: 0.051) }
        }
        .configurationDisplayName("Weekly km")
        .description("This week's distance against your plan, and your run while it's live.")
        .supportedFamilies([.systemSmall])
    }
}

struct RunSmartWeeklyEntry: TimelineEntry {
    let date: Date
    let content: RunSmartWeeklyWidgetContent
}

struct RunSmartWeeklyProvider: TimelineProvider {
    func placeholder(in context: Context) -> RunSmartWeeklyEntry {
        RunSmartWeeklyEntry(date: Date(), content: .init(hasData: true, weekDistanceKm: 0, weekGoalKm: nil, isRunInProgress: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (RunSmartWeeklyEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RunSmartWeeklyEntry>) -> Void) {
        let now = Date()
        let next = RunSmartWeeklyWidgetContent.nextRefresh(after: now, calendar: .current)
        completion(Timeline(entries: [entry(at: now)], policy: .after(next)))
    }

    private func entry(at date: Date) -> RunSmartWeeklyEntry {
        let snapshot = RunSmartWidgetSnapshotStore.shared.load()
        return RunSmartWeeklyEntry(date: date, content: .make(snapshot: snapshot, now: date, calendar: .current))
    }
}

struct RunSmartWeeklyWidgetView: View {
    let entry: RunSmartWeeklyEntry

    private static let lime = Color(red: 0.800, green: 1.000, blue: 0.000)
    private static let muted = Color.white.opacity(0.62)

    private var content: RunSmartWeeklyWidgetContent { entry.content }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(content.isRunInProgress ? "RUN IN PROGRESS" : "THIS WEEK")
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(content.isRunInProgress ? Self.lime : Self.muted)

            Spacer(minLength: 6)

            if content.hasData {
                weekBody
            } else {
                Text("Open RunSmart to see your week")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 6)

            Text(content.isRunInProgress ? "Tap to open" : content.hasData ? "Tap to run" : " ")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Self.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(content.isRunInProgress ? RunSmartRunDeepLink.live : RunSmartRunDeepLink.start)
    }

    @ViewBuilder
    private var weekBody: some View {
        if let progress = content.progress {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.16), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Self.lime, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(width: 56, height: 56)
                numbers
            }
        } else {
            numbers
        }
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(content.distanceLabel)
                .font(.system(size: 26, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(content.goalLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Self.muted)
                .lineLimit(1)
        }
    }
}

#if DEBUG
#Preview("Weekly widget", as: .systemSmall) {
    RunSmartWeeklyWidget()
} timeline: {
    RunSmartWeeklyEntry(date: .now, content: .init(hasData: true, weekDistanceKm: 21.4, weekGoalKm: 30, isRunInProgress: false))
    RunSmartWeeklyEntry(date: .now, content: .init(hasData: true, weekDistanceKm: 21.4, weekGoalKm: 30, isRunInProgress: true))
    RunSmartWeeklyEntry(date: .now, content: .init(hasData: true, weekDistanceKm: 8.2, weekGoalKm: nil, isRunInProgress: false))
    RunSmartWeeklyEntry(date: .now, content: .init(hasData: false, weekDistanceKm: 0, weekGoalKm: nil, isRunInProgress: false))
}
#endif
