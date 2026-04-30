import SwiftUI

struct TodayWorkoutCard: View {
    var recommendation: TodayRecommendation
    var route: RouteSuggestion?
    var onStart: () -> Void
    var onModify: () -> Void
    var onSkip: () -> Void
    var onRoute: () -> Void

    var body: some View {
        HeroCard(accent: .accentEnergy, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.accentEnergy)
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(title: "Today's workout")
                        Text(recommendation.workoutTitle)
                            .font(.headingLG)
                            .foregroundStyle(Color.textPrimary)
                    }
                    Spacer()
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(recommendation.distance)
                        .font(.metricLG)
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        MetricPill(symbol: "stopwatch", text: recommendation.pace)
                        MetricPill(symbol: "mountain.2", text: recommendation.elevation)
                    }
                }

                Button(action: onRoute) {
                    RouteMapView(points: route?.points ?? [], title: route?.name ?? "Choose route")
                        .frame(height: 104)
                        .overlay(alignment: .bottomTrailing) {
                            Label("Route", systemImage: "map")
                                .font(.labelSM)
                                .tracking(0.8)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.58), in: Capsule())
                                .foregroundStyle(Color.accentPrimary)
                                .padding(9)
                        }
                }
                .buttonStyle(.plain)

                Button(action: onStart) {
                    Label("Start Workout", systemImage: "play.fill")
                }
                .buttonStyle(NeonButtonStyle())

                HStack {
                    Button("Modify", action: onModify)
                    Spacer()
                    Button("Skip", action: onSkip)
                }
                .font(.bodyMD.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            }
        }
    }
}
