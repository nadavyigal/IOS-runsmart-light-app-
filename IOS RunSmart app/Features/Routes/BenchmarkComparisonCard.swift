import SwiftUI

struct BenchmarkComparisonLoaderView: View {
    @Environment(\.runSmartServices) private var services
    var run: RecordedRun?

    @State private var state: BenchmarkComparisonLoadState = .empty

    var body: some View {
        Group {
            switch state {
            case .empty:
                EmptyView()
            case .comparison(let comparison):
                BenchmarkComparisonCard(comparison: comparison)
            case .status(let status):
                BenchmarkComparisonStatusCard(status: status)
            }
        }
        .task(id: run?.id) {
            await loadComparison()
        }
    }

    private func loadComparison() async {
        guard var run else {
            state = .empty
            return
        }

        if run.routePoints.isEmpty {
            state = .status(.noRouteData)
            return
        }

        if run.routePoints.count < RouteMatchingService.minimumRoutePoints {
            state = .status(.weakGPS)
            return
        }

        if run.routeMatchResult == nil {
            run.routeMatchResult = await services.matchRoute(for: run)
        }

        guard let match = run.routeMatchResult else {
            state = .status(.noBenchmark)
            return
        }

        switch match.confidence {
        case .possibleMatch:
            state = .status(.weakGPS)
            return
        case .noMatch:
            state = .status(.noBenchmark)
            return
        case .matched:
            break
        }

        if let comparison = await services.benchmarkComparison(for: run) {
            state = .comparison(comparison)
        } else {
            state = .status(.noBenchmark)
        }
    }
}

enum BenchmarkComparisonLoadState: Hashable {
    case empty
    case comparison(BenchmarkRouteComparison)
    case status(BenchmarkComparisonStatus)
}

enum BenchmarkComparisonStatus: Hashable {
    case noRouteData
    case weakGPS
    case noBenchmark

    var title: String {
        switch self {
        case .noRouteData:
            return "No benchmark comparison"
        case .weakGPS:
            return "Benchmark confidence is low"
        case .noBenchmark:
            return "No benchmark route matched"
        }
    }

    var message: String {
        switch self {
        case .noRouteData:
            return "This activity does not include enough map data for route matching. The run is saved, but RunSmart will not compare it to a benchmark."
        case .weakGPS:
            return "GPS shape was not strong enough for a trustworthy benchmark comparison, so RunSmart is not showing pace or PB deltas."
        case .noBenchmark:
            return "Save this route as a benchmark, or run an existing benchmark route, to unlock repeatable comparisons."
        }
    }

    var symbol: String {
        switch self {
        case .noRouteData:
            return "map"
        case .weakGPS:
            return "location.slash"
        case .noBenchmark:
            return "flag"
        }
    }

    var tint: Color {
        switch self {
        case .weakGPS:
            return .accentEnergy
        case .noRouteData, .noBenchmark:
            return .textSecondary
        }
    }
}

private struct BenchmarkComparisonStatusCard: View {
    var status: BenchmarkComparisonStatus

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 16, accent: status.tint) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: status.symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(status.tint)
                    .frame(width: 34, height: 34)
                    .background(status.tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(status.title)
                        .font(.headingMD)
                        .foregroundStyle(Color.textPrimary)
                    Text(status.message)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct BenchmarkComparisonCard: View {
    var comparison: BenchmarkRouteComparison

    private var insights: [String] {
        BenchmarkComparisonPresentation.insights(for: comparison)
    }

    var body: some View {
        RunSmartPanel(cornerRadius: 22, padding: 16, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 14) {
                header

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    BenchmarkMetricTile(
                        title: "Previous",
                        value: previousValue,
                        detail: previousDetail,
                        symbol: "clock.arrow.circlepath",
                        tint: .accentRecovery
                    )
                    BenchmarkMetricTile(
                        title: "Route PB",
                        value: BenchmarkComparisonPresentation.durationLabel(comparison.personalBest.durationSeconds),
                        detail: pbDetail,
                        symbol: "flag.checkered",
                        tint: .accentPrimary
                    )
                    BenchmarkMetricTile(
                        title: "Month Avg",
                        value: BenchmarkComparisonPresentation.paceLabel(comparison.monthlyAverage.averagePaceSecondsPerKm),
                        detail: monthlyDetail,
                        symbol: "calendar",
                        tint: .accentEnergy
                    )
                    BenchmarkMetricTile(
                        title: "Trend",
                        value: BenchmarkComparisonPresentation.trendLabel(comparison.recentTrend),
                        detail: trendDetail,
                        symbol: "chart.line.uptrend.xyaxis",
                        tint: trendTint
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(insights, id: \.self) { insight in
                        Label(insight, systemImage: "sparkle")
                            .font(.bodyMD)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !comparison.hasEnoughHistory {
                    Text("Comparisons get sharper after one more matched run on this benchmark route.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ProgressShareButton(payload: .benchmark(comparison))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Benchmark comparison for \(comparison.routeName)")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 34, height: 34)
                .background(Color.accentPrimary.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Benchmark Route")
                    .font(.labelLG)
                    .foregroundStyle(Color.accentPrimary)
                Text(comparison.routeName)
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            StatusChip(
                text: BenchmarkComparisonPresentation.confidenceLabel(comparison.matchConfidence),
                tint: .accentPrimary
            )
        }
    }

    private var previousValue: String {
        guard let previous = comparison.previousPerformance else { return "First run" }
        return BenchmarkComparisonPresentation.deltaLabel(
            current: comparison.currentPerformance.durationSeconds,
            baseline: previous.durationSeconds
        )
    }

    private var previousDetail: String {
        guard let previous = comparison.previousPerformance else { return "No prior route match" }
        return "vs \(BenchmarkComparisonPresentation.durationLabel(previous.durationSeconds))"
    }

    private var pbDetail: String {
        comparison.personalBest.runID == comparison.currentPerformance.runID ? "New best" : "Best effort"
    }

    private var monthlyDetail: String {
        let count = comparison.monthlyAverage.runCount
        if comparison.monthlyAverage.hasEnoughData {
            return "\(count) runs this month"
        }
        return count == 1 ? "1 run this month" : "Needs more runs"
    }

    private var trendDetail: String {
        switch comparison.recentTrend {
        case .improving: "Recent pace is moving up"
        case .steady: "Recent pace is stable"
        case .slowing: "Recent pace is slower"
        case .notEnoughData: "Needs more history"
        }
    }

    private var trendTint: Color {
        switch comparison.recentTrend {
        case .improving: .accentPrimary
        case .steady: .accentRecovery
        case .slowing: .accentEnergy
        case .notEnoughData: .textSecondary
        }
    }
}

private struct BenchmarkMetricTile: View {
    var title: String
    var value: String
    var detail: String
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.bold())
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.labelSM)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            Text(value)
                .font(.metricXS)
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(12)
        .background(Color.surfaceCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.border, lineWidth: 1))
    }
}

#if DEBUG
#Preview {
    BenchmarkComparisonCard(
        comparison: BenchmarkRouteComparison(
            routeID: RunSmartPreviewData.savedRouteIDs.0,
            routeName: "Park Loop",
            matchConfidence: .matched,
            currentPerformance: BenchmarkRunPerformance(
                runID: UUID(),
                source: .runSmart,
                startedAt: Date(),
                durationSeconds: 1_545,
                paceSecondsPerKm: 297,
                averageHeartRateBPM: 146
            ),
            previousPerformance: BenchmarkRunPerformance(
                runID: UUID(),
                source: .garmin,
                startedAt: Date().addingTimeInterval(-86_400 * 7),
                durationSeconds: 1_580,
                paceSecondsPerKm: 304,
                averageHeartRateBPM: 149
            ),
            personalBest: BenchmarkRunPerformance(
                runID: UUID(),
                source: .runSmart,
                startedAt: Date().addingTimeInterval(-86_400 * 3),
                durationSeconds: 1_540,
                paceSecondsPerKm: 296,
                averageHeartRateBPM: 145
            ),
            allTimeAverage: BenchmarkPerformanceAverage(
                routeID: RunSmartPreviewData.savedRouteIDs.0,
                runCount: 4,
                averageDurationSeconds: 1_590,
                averagePaceSecondsPerKm: 306,
                bestPaceSecondsPerKm: 296,
                averageHeartRateBPM: 147
            ),
            monthlyAverage: MonthlyBenchmarkAverage(
                routeID: RunSmartPreviewData.savedRouteIDs.0,
                monthStart: Date(),
                runCount: 3,
                averageDurationSeconds: 1_570,
                averagePaceSecondsPerKm: 302,
                bestPaceSecondsPerKm: 296,
                averageHeartRateBPM: 146,
                hasEnoughData: true
            ),
            recentTrend: .improving
        )
    )
    .padding()
    .background(Color.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
