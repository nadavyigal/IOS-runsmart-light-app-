import SwiftUI
import UIKit

enum ProgressShareKind: String, Hashable {
    case runReport = "Run Report"
    case benchmark = "Benchmark"
    case milestone = "Milestone"
}

struct ProgressSharePayload: Hashable {
    var kind: ProgressShareKind
    var title: String
    var subtitle: String
    var metrics: [ProgressShareMetric]
    var insight: String
    var privacyNote: String
    /// The coach line for run share images and video: AI-written only, else empty.
    var mediaInsight: String = ""

    var shareText: String {
        let metricText = metrics.map { "\($0.title): \($0.value)" }.joined(separator: " • ")
        return [
            "RunSmart \(kind.rawValue)",
            title,
            subtitle,
            metricText,
            insight,
            privacyNote
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
    }

    static func runReport(_ report: RunReportDetail) -> ProgressSharePayload {
        ProgressSharePayload(
            kind: .runReport,
            title: report.title,
            subtitle: report.dateLabel,
            metrics: [
                ProgressShareMetric(title: "Distance", value: report.distance),
                ProgressShareMetric(title: "Moving time", value: report.duration),
                ProgressShareMetric(title: "Avg Pace", value: report.averagePace)
            ],
            insight: report.notes.summary,
            privacyNote: "Private share: no map, GPS points, or exact route are included.",
            mediaInsight: report.shareHighlight ?? ""
        )
    }

    static func benchmark(_ comparison: BenchmarkRouteComparison) -> ProgressSharePayload {
        let current = comparison.currentPerformance
        // A route variant is a different distance, so its total time is not comparable to the
        // route PB; share pace, like the card does.
        let headline: [ProgressShareMetric] = current.isRouteVariant
            ? [
                ProgressShareMetric(title: "This Run", value: "\(BenchmarkComparisonPresentation.paceLabel(current.paceSecondsPerKm)) /km"),
                ProgressShareMetric(title: "Best Pace", value: "\(BenchmarkComparisonPresentation.paceLabel(comparison.allTimeAverage.bestPaceSecondsPerKm)) /km")
            ]
            : [
                ProgressShareMetric(title: "This Run", value: BenchmarkComparisonPresentation.durationLabel(current.durationSeconds)),
                ProgressShareMetric(title: "Route PB", value: BenchmarkComparisonPresentation.durationLabel(comparison.personalBest.durationSeconds))
            ]
        return ProgressSharePayload(
            kind: .benchmark,
            title: comparison.routeName,
            subtitle: comparison.currentPerformance.startedAt.formatted(date: .abbreviated, time: .omitted),
            metrics: headline + [
                ProgressShareMetric(title: "Month Avg", value: BenchmarkComparisonPresentation.paceLabel(comparison.monthlyAverage.averagePaceSecondsPerKm))
            ],
            insight: BenchmarkComparisonPresentation.insights(for: comparison).first ?? "Benchmark progress saved privately in RunSmart.",
            privacyNote: "Private share: route name and stats only. No map or GPS points are included."
        )
    }

    /// `value` is optional: a runner with no streak yet has no progress figure
    /// to share, and an empty metric would share as a dangling "Progress: ".
    static func milestone(title: String, subtitle: String, value: String?, insight: String) -> ProgressSharePayload {
        ProgressSharePayload(
            kind: .milestone,
            title: title,
            subtitle: subtitle,
            metrics: value.map { [ProgressShareMetric(title: "Progress", value: $0)] } ?? [],
            insight: insight,
            privacyNote: "Private share: no location data is included."
        )
    }
}

struct ProgressShareMetric: Hashable {
    var title: String
    var value: String
}

struct ProgressShareCard: View {
    var payload: ProgressSharePayload
    /// Set only when the runner opted in to the route map on a run share.
    var routeImage: UIImage? = nil

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 16, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionLabel(title: payload.kind.rawValue)
                    Spacer()
                    RunSmartLogoMark(size: 28, filled: false, glow: false)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(payload.title)
                        .font(.headingMD)
                        .foregroundStyle(Color.textPrimary)
                    Text(payload.subtitle)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }

                if let routeImage {
                    Image(uiImage: routeImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("Route map")
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: min(max(payload.metrics.count, 1), 3)), spacing: 8) {
                    ForEach(payload.metrics, id: \.self) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textTertiary)
                            Text(metric.value)
                                .font(.bodyMD.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.surfaceElevated.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                Text(payload.insight)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(payload.privacyNote, systemImage: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ProgressShareButton: View {
    var payload: ProgressSharePayload
    /// Set only when the runner opted in to the route map. The map is shared as an image with the text.
    var routeImage: UIImage? = nil

    var body: some View {
        Group {
            if let routeImage {
                ShareLink(
                    item: Image(uiImage: routeImage),
                    message: Text(payload.shareText),
                    preview: SharePreview(payload.title, image: Image(uiImage: routeImage))
                ) {
                    label
                }
            } else {
                ShareLink(item: payload.shareText) {
                    label
                }
            }
        }
        // WP-45: ShareLink exposes no tap or completion callback, so the tap is
        // observed via a simultaneous gesture. share_progress_completed stays
        // unwired until sharing moves to UIActivityViewController with a
        // completionWithItemsHandler — not worth that migration for the event.
        .simultaneousGesture(TapGesture().onEnded {
            Analytics.trackShareProgressTapped(payloadKind: payload.kind.rawValue)
        })
        .accessibilityHint(routeImage == nil
            ? "Shares a private progress summary without raw coordinates or a route map."
            : "Shares a progress summary with a route map. The first and last 200 meters are not shown.")
    }

    private var label: some View {
        Label("Share Progress", systemImage: "square.and.arrow.up")
            .font(.buttonLabel)
            .foregroundStyle(Color.accentPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.accentPrimary.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(Color.accentPrimary.opacity(0.50), lineWidth: 1))
    }
}

/// Post-run share: the private card and button, plus an opt-in route map (off by default).
struct RunShareSection: View {
    var payload: ProgressSharePayload
    var routePoints: [RunRoutePoint]
    var run: RecordedRun? = nil

    @State private var includeMap = false
    @State private var routeImage: UIImage?
    @State private var isRendering = false
    @State private var renderFailed = false

    /// Nil when the route is too short (or missing) to show once both ends are cut.
    private var shareableRoute: [RunRoutePoint]? {
        RouteSharePrivacy.shareableRoute(routePoints)
    }

    private var activePayload: ProgressSharePayload {
        includeMap && routeImage != nil ? payload.includingRouteMap() : payload
    }

    @ViewBuilder var body: some View {
        if let run {
            RunMediaShareEntry(run: run, insight: payload.mediaInsight)
        } else {
            legacySummary
        }
    }

    private var legacySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressShareCard(payload: activePayload, routeImage: includeMap ? routeImage : nil)

            if shareableRoute != nil {
                Toggle(isOn: $includeMap) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include route map")
                            .font(.bodyMD.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text(renderFailed
                            ? "The map could not be drawn. Sharing the summary only."
                            : "The first and last 200 m are left out.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .tint(Color.accentPrimary)
                .padding(.horizontal, 4)
                .accessibilityHint("Adds a map of your route to the share, without the first and last 200 meters.")
            }

            ProgressShareButton(payload: activePayload, routeImage: includeMap ? routeImage : nil)
                .disabled(includeMap && isRendering)
                .overlay {
                    if includeMap && isRendering { ProgressView() }
                }
        }
        .task(id: includeMap) {
            guard includeMap else { return }
            guard routeImage == nil else { return }
            guard let route = shareableRoute else {
                includeMap = false
                return
            }
            isRendering = true
            renderFailed = false
            let image = await RouteSnapshotRenderer.render(points: route)
            isRendering = false
            if let image {
                routeImage = image
            } else {
                renderFailed = true
                includeMap = false
            }
        }
        .onChange(of: routePoints.count) { _, _ in
            routeImage = nil
            if includeMap { includeMap = false }
        }
    }
}
