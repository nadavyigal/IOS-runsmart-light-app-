import SwiftUI

struct SaveRouteSheet: View {
    @Environment(\.runSmartServices) private var services
    @Environment(\.dismiss) private var dismiss

    var run: RecordedRun

    @State private var routeName: String = ""
    @State private var routeNotes: String = ""
    @State private var selectedTags: Set<String> = []
    @State private var isFavorite = false
    @State private var makeBenchmark = false
    @State private var isSaving = false
    @State private var saveResult: SaveResult?

    private let availableTags = ["Easy", "Workout", "Hilly", "Flat", "Scenic", "Loop", "Out & Back", "Race Prep"]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    RouteMapView(points: run.routePoints, title: "Route preview")
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    routeStatsRow

                    nameField

                    tagPicker

                    notesField

                    togglesSection

                    if let result = saveResult {
                        resultBanner(result)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.black.opacity(0.52).ignoresSafeArea())
            .navigationTitle("Save Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(Color.accentPrimary)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(routeName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving || saveResult == .saved)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { prefillName() }
    }

    // MARK: - Subviews

    private var routeStatsRow: some View {
        HStack(spacing: 8) {
            statPill(title: "Distance", value: String(format: "%.2f km", run.distanceMeters / 1_000))
            statPill(title: "Time", value: RunRecorder.timeLabel(run.movingTimeSeconds))
            statPill(title: "Points", value: "\(run.routePoints.count)")
        }
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.labelSM)
                .foregroundStyle(Color.textSecondary)
            Text(value)
                .font(.metricXS)
                .monospacedDigit()
                .foregroundStyle(Color.accentPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(Color.surfaceCard.opacity(0.76), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.border, lineWidth: 1))
    }

    private var nameField: some View {
        RunSmartPanel(cornerRadius: 18, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ROUTE NAME")
                    .font(.labelSM)
                    .foregroundStyle(Color.textTertiary)
                TextField("e.g. Morning Park Loop", text: $routeName)
                    .font(.bodyMD)
                    .textInputAutocapitalization(.words)
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }

    private var tagPicker: some View {
        RunSmartPanel(cornerRadius: 18, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("TAGS")
                    .font(.labelSM)
                    .foregroundStyle(Color.textTertiary)

                FlowLayout(spacing: 8) {
                    ForEach(availableTags, id: \.self) { tag in
                        let isSelected = selectedTags.contains(tag)
                        Button {
                            if isSelected { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                        } label: {
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isSelected ? Color.black : Color.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isSelected ? Color.accentPrimary : Color.surfaceCard.opacity(0.6), in: Capsule())
                                .overlay(Capsule().stroke(isSelected ? Color.clear : Color.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var notesField: some View {
        RunSmartPanel(cornerRadius: 18, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOTES")
                    .font(.labelSM)
                    .foregroundStyle(Color.textTertiary)
                TextField("Optional notes about this route", text: $routeNotes, axis: .vertical)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2...5)
            }
        }
    }

    private var togglesSection: some View {
        RunSmartPanel(cornerRadius: 18, padding: 14) {
            VStack(spacing: 0) {
                Toggle(isOn: $isFavorite) {
                    HStack(spacing: 10) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(isFavorite ? .pink : Color.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Favorite")
                                .font(.bodyMD.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                            Text("Quick access in your route library.")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
                .tint(Color.accentPrimary)

                Divider()
                    .padding(.vertical, 10)

                Toggle(isOn: $makeBenchmark) {
                    HStack(spacing: 10) {
                        Image(systemName: makeBenchmark ? "chart.line.uptrend.xyaxis.circle.fill" : "chart.line.uptrend.xyaxis")
                            .foregroundStyle(makeBenchmark ? Color.accentPrimary : Color.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Benchmark Route")
                                .font(.bodyMD.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                            Text("Track your progress each time you run this route.")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
                .tint(Color.accentPrimary)
            }
        }
    }

    @ViewBuilder
    private func resultBanner(_ result: SaveResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: result == .saved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(result == .saved ? Color.accentSuccess : Color.accentHeart)
            Text(result == .saved ? "Route saved to your library." : "Failed to save. Try again.")
                .font(.bodyMD)
                .foregroundStyle(result == .saved ? Color.accentSuccess : Color.accentHeart)
            Spacer()
        }
        .padding(14)
        .background((result == .saved ? Color.accentSuccess : Color.accentHeart).opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Logic

    private func prefillName() {
        let km = run.distanceMeters / 1_000
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dateStr = formatter.string(from: run.startedAt)
        routeName = String(format: "%.1f km run · %@", km, dateStr)
    }

    private func save() async {
        let trimmedName = routeName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        var route = SavedRoute.from(run: run, name: trimmedName, tags: Array(selectedTags), notes: routeNotes)
        route.isFavorite = isFavorite

        let saved = await services.saveRoute(route)
        if saved && makeBenchmark {
            _ = await services.enableBenchmark(for: route.id)
        }

        saveResult = saved ? .saved : .failed
        if saved {
            RunSmartHaptics.success()
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
        }
    }

    enum SaveResult {
        case saved
        case failed
    }
}

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if index < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}

#if DEBUG
#Preview("Save Route Sheet") {
    ZStack {
        RunSmartBackground()
        Color.clear
    }
    .sheet(isPresented: .constant(true)) {
        SaveRouteSheet(run: RunSmartPreviewData.recordedRuns[0])
            .environment(\.runSmartServices, MockRunSmartServices())
            .preferredColorScheme(.dark)
    }
}
#endif
