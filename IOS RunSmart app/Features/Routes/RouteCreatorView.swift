import CoreLocation
import SwiftUI

struct RouteCreatorView: View {
    @Environment(\.runSmartServices) private var services
    @State private var targetDistance = 8.0
    @State private var elevation = "Rolling"
    @State private var surface = "Road"
    @State private var allSuggestions: [RouteSuggestion] = []
    @State private var selectedRouteID: String?
    @State private var isLoading = false
    @State private var locationUnavailable = false
    @State private var mapKitFailed = false
    @State private var distanceFilter: Double? = nil

    private let filterOptions: [Double?] = [nil, 3, 5, 8, 10, 15]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Route shape controls
            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Route shape")
                    HStack {
                        Text("Distance")
                        Spacer()
                        Text(String(format: "%.1f km", targetDistance))
                            .font(.metricSM)
                            .foregroundStyle(Color.accentPrimary)
                    }
                    Slider(value: $targetDistance, in: 3...24, step: 0.5)
                        .tint(Color.accentPrimary)
                    RouteSegmentedControl(title: "Elevation", options: ["Flat", "Rolling", "Hilly"], selection: $elevation)
                    RouteSegmentedControl(title: "Surface", options: ["Road", "Trail", "Mixed"], selection: $surface)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Distance filter
            RouteDistanceFilterBar(options: filterOptions, selected: $distanceFilter)
                .padding(.vertical, 12)

            // Route list
            VStack(alignment: .leading, spacing: 10) {
                if isLoading {
                    routeLoadingState
                } else if locationUnavailable && allSuggestions.isEmpty {
                    RouteDiscoveryEmptyCard(
                        title: "Location unavailable",
                        message: "Enable location access to generate nearby loops, or use saved and past routes below.",
                        systemImage: "location.slash"
                    )
                } else if allSuggestions.isEmpty && !mapKitFailed {
                    RouteDiscoveryEmptyCard(
                        title: "No routes yet",
                        message: "Tap Generate Route to create a nearby loop based on your current location.",
                        systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                    )
                } else {
                    routeBuckets
                }
            }
            .padding(.horizontal, 16)

            // Generate button
            Button {
                Task { await loadSuggestions() }
            } label: {
                Label("Generate Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(isLoading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
        .task {
            await loadSuggestions()
        }
    }

    // MARK: - Buckets

    private var displayed: [RouteSuggestion] {
        let filtered = RouteSuggestionRanker.filter(allSuggestions, targetDistanceKm: distanceFilter)
        return RouteSuggestionRanker.rank(filtered, targetDistanceKm: distanceFilter ?? targetDistance, elevationPreference: elevation)
    }

    private var benchmarks: [RouteSuggestion] {
        displayed.filter { $0.kind == .benchmark }
    }

    private var myRoutes: [RouteSuggestion] {
        displayed.filter { $0.kind == .saved || $0.kind == .past }
    }

    private var generatedNearby: [RouteSuggestion] {
        displayed.filter { $0.kind == .generated }
    }

    @ViewBuilder
    private var routeBuckets: some View {
        let hasAny = !benchmarks.isEmpty || !myRoutes.isEmpty || !generatedNearby.isEmpty

        if !hasAny {
            RouteDiscoveryEmptyCard(
                title: "No matching routes",
                message: "Try a different distance filter or generate a new route.",
                systemImage: "slider.horizontal.3"
            )
        } else {
            if !benchmarks.isEmpty {
                RouteDiscoverySectionHeader(title: "Benchmarks", count: benchmarks.count)
                ForEach(benchmarks) { r in
                    FullBleedRouteCard(suggestion: r, isSelected: r.id == selectedRouteID) {
                        selectedRouteID = r.id
                    }
                }
            }

            if !myRoutes.isEmpty {
                RouteDiscoverySectionHeader(title: "My Routes", count: myRoutes.count)
                ForEach(myRoutes) { r in
                    FullBleedRouteCard(suggestion: r, isSelected: r.id == selectedRouteID) {
                        selectedRouteID = r.id
                    }
                }
            }

            if !generatedNearby.isEmpty {
                RouteDiscoverySectionHeader(title: "Generated Nearby", count: generatedNearby.count)
                ForEach(generatedNearby) { r in
                    FullBleedRouteCard(suggestion: r, isSelected: r.id == selectedRouteID) {
                        selectedRouteID = r.id
                    }
                }
            } else if mapKitFailed && !locationUnavailable {
                routeMapKitFailureState
            }
        }
    }

    @ViewBuilder
    private var routeMapKitFailureState: some View {
        HStack(spacing: 12) {
            Image(systemName: "map.fill")
                .foregroundStyle(Color.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Route generation unavailable")
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Couldn't generate a nearby loop. Check your connection and tap Retry.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button {
                Task { await loadSuggestions() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Color.accentPrimary)
            }
            .disabled(isLoading)
        }
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var routeLoadingState: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Color.accentPrimary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Finding routes")
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Loading saved routes and nearby loops.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Loading

    private func loadSuggestions() async {
        isLoading = true
        locationUnavailable = false
        mapKitFailed = false
        defer { isLoading = false }

        async let rankedTask = services.rankedRouteSuggestions(targetDistanceKm: targetDistance)
        let location = await LocationLookupService.shared.currentLocation()
        let generated = await generatedSuggestions(around: location)
        let ranked = await rankedTask
        locationUnavailable = location == nil
        mapKitFailed = location != nil && generated.isEmpty
        allSuggestions = mergedSuggestions(ranked + generated)
        if selectedRouteID == nil {
            selectedRouteID = allSuggestions.first?.id
        }
    }

    private func generatedSuggestions(around location: CLLocationCoordinate2D?) async -> [RouteSuggestion] {
        guard let location else { return [] }
        let generated = await services.nearbyLoopRoutes(around: location, distancesKm: [targetDistance])
        return generated.map { suggestion in
            var enriched = suggestion
            enriched.recommendationReason = RouteSuggestionRanker.reason(
                kind: .generated,
                distanceKm: suggestion.distanceKm,
                targetDistanceKm: targetDistance,
                isFavorite: false,
                daysSinceLastRun: nil,
                elevationPreference: elevation
            )
            return enriched
        }
    }

    private func mergedSuggestions(_ suggestions: [RouteSuggestion]) -> [RouteSuggestion] {
        var seen = Set<String>()
        return suggestions.filter { suggestion in
            guard !seen.contains(suggestion.id) else { return false }
            seen.insert(suggestion.id)
            return true
        }
    }
}

// MARK: - Private sub-views (kept internal)

private struct RouteSegmentedControl: View {
    var title: String
    var options: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.labelSM)
                .tracking(1.1)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 7) {
                ForEach(options, id: \.self) { option in
                    Button { selection = option } label: {
                        Text(option)
                            .font(.labelSM)
                            .foregroundStyle(selection == option ? Color.black : Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selection == option ? Color.accentPrimary : Color.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
