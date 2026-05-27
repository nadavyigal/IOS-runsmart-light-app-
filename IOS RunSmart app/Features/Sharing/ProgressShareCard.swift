import SwiftUI

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
                ProgressShareMetric(title: "Time", value: report.duration),
                ProgressShareMetric(title: "Avg Pace", value: report.averagePace)
            ],
            insight: report.notes.summary,
            privacyNote: "Private share: no map, GPS points, or exact route are included."
        )
    }

    static func benchmark(_ comparison: BenchmarkRouteComparison) -> ProgressSharePayload {
        let current = comparison.currentPerformance
        return ProgressSharePayload(
            kind: .benchmark,
            title: comparison.routeName,
            subtitle: comparison.currentPerformance.startedAt.formatted(date: .abbreviated, time: .omitted),
            metrics: [
                ProgressShareMetric(title: "This Run", value: BenchmarkComparisonPresentation.durationLabel(current.durationSeconds)),
                ProgressShareMetric(title: "Route PB", value: BenchmarkComparisonPresentation.durationLabel(comparison.personalBest.durationSeconds)),
                ProgressShareMetric(title: "Month Avg", value: BenchmarkComparisonPresentation.paceLabel(comparison.monthlyAverage.averagePaceSecondsPerKm))
            ],
            insight: BenchmarkComparisonPresentation.insights(for: comparison).first ?? "Benchmark progress saved privately in RunSmart.",
            privacyNote: "Private share: route name and stats only. No map or GPS points are included."
        )
    }

    static func milestone(title: String, subtitle: String, value: String, insight: String) -> ProgressSharePayload {
        ProgressSharePayload(
            kind: .milestone,
            title: title,
            subtitle: subtitle,
            metrics: [ProgressShareMetric(title: "Progress", value: value)],
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

    var body: some View {
        ShareLink(item: payload.shareText) {
            Label("Share Progress", systemImage: "square.and.arrow.up")
                .font(.buttonLabel)
                .foregroundStyle(Color.accentPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.accentPrimary.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(Color.accentPrimary.opacity(0.50), lineWidth: 1))
        }
        .accessibilityHint("Shares a private progress summary without raw coordinates or a route map.")
    }
}
