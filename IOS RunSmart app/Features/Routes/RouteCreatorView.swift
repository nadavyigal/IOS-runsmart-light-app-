import SwiftUI

struct RouteCreatorView: View {
    @Environment(\.runSmartServices) private var services
    @State private var distance = 8.0
    @State private var elevation = "Rolling"
    @State private var surface = "Road"
    @State private var pastRoutes: [RouteSuggestion] = []
    @State private var nearbyRoutes: [RouteSuggestion] = []
    @State private var selectedRouteID: String?
    @State private var isLoadingPastRoutes = false
    @State private var isLoadingNearbyRoutes = false
    @State private var locationUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HeroCard(accent: .accentRecovery) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Route creator")
                    Text("Build a route for the workout")
                        .font(.headingLG)
                    RouteMapView(points: selectedRoute?.points ?? [], title: selectedRoute?.name ?? "Preview route")
                        .frame(height: 150)
                    Text(routeDetail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
            }

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Route shape")
                    HStack {
                        Text("Distance")
                        Spacer()
                        Text(String(format: "%.1f km", distance))
                            .font(.metricSM)
                            .foregroundStyle(Color.accentPrimary)
                    }
                    Slider(value: $distance, in: 3...24, step: 0.5)
                        .tint(Color.accentPrimary)
                    RouteSegmentedControl(title: "Elevation", options: ["Flat", "Rolling", "Hilly"], selection: $elevation)
                    RouteSegmentedControl(title: "Surface", options: ["Road", "Trail", "Mixed"], selection: $surface)
                }
            }

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Nearby")
                    if isLoadingNearbyRoutes {
                        RouteLoadingRow(title: "Finding nearby loops", detail: "Using your current location without blocking this screen.")
                    } else if locationUnavailable {
                        RouteEmptyRow(title: "GPS unavailable", detail: "Open the app outdoors or try again after location access settles.")
                    } else if nearbyRoutes.isEmpty {
                        RouteEmptyRow(title: "No nearby loops yet", detail: "Generate a route after GPS finds your current location.")
                    } else {
                        ForEach(nearbyRoutes) { route in
                            RouteSuggestionButton(route: route, selected: route.id == selectedRouteID) {
                                selectedRouteID = route.id
                            }
                        }
                    }
                }
            }

            ContentCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Past routes")
                    if isLoadingPastRoutes {
                        RouteLoadingRow(title: "Loading saved routes", detail: "Checking your recent GPS activity.")
                    } else if pastRoutes.isEmpty {
                        RouteEmptyRow(title: "No saved routes", detail: "Record one GPS run and it will appear here for quick reuse.")
                    } else {
                        ForEach(pastRoutes) { route in
                            RouteSuggestionButton(route: route, selected: route.id == selectedRouteID) {
                                selectedRouteID = route.id
                            }
                        }
                    }
                }
            }

            Button { Task { await loadNearbyRoutes() } } label: {
                Label("Generate Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(isLoadingNearbyRoutes)
        }
        .task {
            await loadPastRoutes()
            await loadNearbyRoutes()
        }
    }

    private var allRoutes: [RouteSuggestion] {
        nearbyRoutes + pastRoutes
    }

    private var selectedRoute: RouteSuggestion? {
        allRoutes.first(where: { $0.id == selectedRouteID }) ?? allRoutes.first
    }

    private var routeDetail: String {
        guard let selectedRoute else {
            return "Route suggestions will appear here as GPS and recent activity load."
        }
        return "\(String(format: "%.1f", selectedRoute.distanceKm)) km - \(selectedRoute.elevationGainMeters)m gain - \(selectedRoute.estimatedDurationMinutes) min"
    }

    private func loadPastRoutes() async {
        isLoadingPastRoutes = true
        defer { isLoadingPastRoutes = false }
        pastRoutes = await services.routeSuggestions()
        if selectedRouteID == nil {
            selectedRouteID = allRoutes.first?.id
        }
    }

    private func loadNearbyRoutes() async {
        isLoadingNearbyRoutes = true
        locationUnavailable = false
        defer { isLoadingNearbyRoutes = false }

        guard let coordinate = await LocationLookupService.shared.currentLocation() else {
            locationUnavailable = true
            nearbyRoutes = []
            if selectedRouteID == nil {
                selectedRouteID = allRoutes.first?.id
            }
            return
        }

        nearbyRoutes = await services.nearbyLoopRoutes(around: coordinate, distancesKm: [distance])
        selectedRouteID = nearbyRoutes.first?.id ?? selectedRouteID ?? allRoutes.first?.id
    }
}

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

private struct RouteSuggestionButton: View {
    var route: RouteSuggestion
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentPrimary : Color.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(route.name)
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(String(format: "%.1f", route.distanceKm)) km - \(route.elevationGainMeters)m gain - \(route.estimatedDurationMinutes) min")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.surfaceElevated.opacity(selected ? 0.95 : 0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Color.accentPrimary.opacity(0.44) : Color.border.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct RouteLoadingRow: View {
    var title: String
    var detail: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Color.accentPrimary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.bodyMD.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surfaceElevated.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RouteEmptyRow: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.bodyMD.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surfaceElevated.opacity(0.46), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
