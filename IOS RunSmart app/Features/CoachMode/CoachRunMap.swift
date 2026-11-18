import SwiftUI

/// C6 map block (Story 6.2). One per run in the day detail.
struct CoachRunMapBlock: View {
    let run: CoachRunSummary
    let calendar: Calendar
    /// The link is gone: the screen returns to the athlete detail, which shows
    /// "{Athlete} is no longer in your group" (Story 2.4).
    let onRevoked: () -> Void
    @StateObject private var model: CoachRunMapModel

    init(run: CoachRunSummary, calendar: Calendar,
         service: any CoachRunRouteFetching = SupabaseCoachRunRouteService(),
         onRevoked: @escaping () -> Void) {
        self.run = run
        self.calendar = calendar
        self.onRevoked = onRevoked
        _model = StateObject(wrappedValue: CoachRunMapModel(runID: run.id, service: service))
    }

    var body: some View {
        CoachRunMapContent(
            phase: model.phase,
            altText: CoachRunRouteMapping.altText(completedAt: run.completedAt, distanceKm: run.distanceKm, calendar: calendar),
            retry: { Task { await model.load() } }
        )
        .task { await model.load() }
        .onChange(of: model.phase) { _, phase in
            if phase == .revoked { onRevoked() }
        }
    }
}

/// The block's look for each phase. Split out so it can be drawn in tests.
struct CoachRunMapContent: View {
    let phase: CoachRunMapModel.Phase
    let altText: String
    let retry: () -> Void
    @State private var showsFullScreen = false

    var body: some View {
        switch phase {
        case .loading:
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.textSecondary.opacity(0.15))
                ProgressView().tint(Color.textSecondary)
            }
            .frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading the map")
        case .failed:
            HStack {
                Text(CoachRunRouteMapping.loadFailed)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button("Retry", action: retry)
                    .foregroundStyle(Color.accentPrimary)
                    .frame(minHeight: 44)
            }
            .padding(12)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .revoked:
            EmptyView()
        case .loaded(let state):
            switch state {
            case .map(let route):
                map(route)
            case .hidden, .routeHidden, .noMap:
                // Plain secondary text: never error styling.
                Text(state.copy ?? "")
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("coach-run-map-state")
            }
        }
    }

    private func map(_ route: [CoachRouteCoordinate]) -> some View {
        let points = CoachRunRouteMapping.points(route)
        return VStack(alignment: .leading, spacing: 6) {
            Button { showsFullScreen = true } label: {
                RouteMapView(points: points, title: nil)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    // Non-interactive inline; the tap opens the full-screen map.
                    .allowsHitTesting(false)
                    // The map itself is never mirrored in RTL; the caption below follows the language.
                    .environment(\.layoutDirection, .leftToRight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(altText)
            .accessibilityHint("Opens the map full screen")
            Text(CoachRunRouteMapping.caption)
                .font(.labelLG)
                .foregroundStyle(Color.textSecondary)
        }
        .fullScreenCover(isPresented: $showsFullScreen) {
            CoachRunFullMap(points: points, altText: altText)
        }
    }
}

/// Full-screen route: pinch and pan only here.
private struct CoachRunFullMap: View {
    let points: [RunRoutePoint]
    let altText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                RouteMapView(points: points, title: nil)
                    .accessibilityLabel(altText)
                    .environment(\.layoutDirection, .leftToRight)
                Text(CoachRunRouteMapping.caption)
                    .font(.labelLG)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 12)
            }
            .padding(.bottom, 12)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
