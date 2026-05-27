import SwiftUI

struct FlexWeekDiffView: View {
    var originalWeek: [PlannedWorkout]
    var outcome: FlexWeekOutcome
    var isLoading: Bool
    var onCancel: () -> Void
    var onConfirm: () -> Void
    var onKeepOriginal: () -> Void

    @State private var showUnchanged = false

    private var changedWorkouts: [(original: PlannedWorkout, updated: PlannedWorkout, rationale: String)] {
        let originalByID = Dictionary(uniqueKeysWithValues: originalWeek.map { ($0.id, $0) })
        let updatedByID = Dictionary(uniqueKeysWithValues: outcome.restructuredWeek.map { ($0.id, $0) })

        var rows: [UUID: (PlannedWorkout, PlannedWorkout, String)] = [:]
        for change in outcome.changes {
            let originalID = change.originalWorkoutID ?? change.workoutID
            guard let original = originalByID[originalID] ?? originalByID[change.workoutID],
                  let updated = updatedByID[change.workoutID] ?? updatedByID[originalID]
            else { continue }

            let showRow = !workoutsEqual(original, updated) ||
                change.rationale.localizedCaseInsensitiveContains("Taper week")
            guard showRow else { continue }

            rows[updated.id] = (original, updated, change.rationale)
        }

        return rows.values.sorted { $0.1.scheduledDate < $1.1.scheduledDate }
    }

    private var unchangedWorkouts: [PlannedWorkout] {
        let changedIDs = Set(changedWorkouts.flatMap { [$0.original.id, $0.updated.id] })
        return outcome.restructuredWeek.filter { !changedIDs.contains($0.id) }
    }

    var body: some View {
        ZStack {
            RunSmartBackground(context: .plan)
                .ignoresSafeArea()

            if isLoading {
                loadingState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        hero
                        if !outcome.safetyWarnings.isEmpty {
                            safetyBanner
                        }
                        changedSection
                        unchangedSection
                    }
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 20)
                    .padding(.top, 78)
                    .padding(.bottom, 168)
                }
            }

            topBar
        }
        .safeAreaInset(edge: .bottom) {
            if !isLoading {
                bottomBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.bodyMD.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(Color.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Changes")
                        .font(.bodyMD.weight(.bold))
                    Text(isLoading ? "Coach is rewriting your week…" : sourceLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var hero: some View {
        RunSmartPanel(cornerRadius: 22, padding: 18, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "Proposed Week")
                Text("Confirm only if this rewrite matches what you need. Every change includes Coach's rationale.")
                    .font(.bodyLG)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var safetyBanner: some View {
        RunSmartPanel(cornerRadius: 18, padding: 14, accent: .accentEnergy) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Safety notes", systemImage: "info.circle.fill")
                    .font(.bodyMD.weight(.bold))
                    .foregroundStyle(Color.accentEnergy)
                ForEach(outcome.safetyWarnings, id: \.self) { warning in
                    Text(warning)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var changedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Changed", trailing: "\(changedWorkouts.count)")

            if changedWorkouts.isEmpty {
                RunSmartPanel(cornerRadius: 18, padding: 14) {
                    Text("No visible workout changes in this proposal.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                ForEach(changedWorkouts, id: \.updated.id) { item in
                    FlexWeekDiffRow(
                        original: item.original,
                        updated: item.updated,
                        rationale: item.rationale
                    )
                }
            }
        }
    }

    private var unchangedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    showUnchanged.toggle()
                }
            } label: {
                HStack {
                    Text("No change")
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text("(\(unchangedWorkouts.count))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Image(systemName: showUnchanged ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if showUnchanged {
                VStack(spacing: 8) {
                    ForEach(unchangedWorkouts) { workout in
                        FlexWeekUnchangedRow(workout: workout)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 18) {
            Spacer()
            RunSmartPanel(cornerRadius: 22, padding: 20, accent: .accentPrimary) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(title: "Flex Week")
                    Text("Coach is rewriting your week…")
                        .font(.headingMD.weight(.bold))
                    VStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.shimmer)
                                .frame(height: 54)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            Spacer()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button(action: onConfirm) {
                Text("Confirm New Week")
            }
            .buttonStyle(NeonButtonStyle())

            Button(action: onKeepOriginal) {
                Text("Keep Original Plan")
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
        }
    }

    private var sourceLabel: String {
        switch outcome.source {
        case .ai: "AI proposal"
        case .deterministicFallback: "Safe fallback proposal"
        case .offlineQueued: "Offline-safe proposal"
        }
    }

    private func workoutsEqual(_ lhs: PlannedWorkout, _ rhs: PlannedWorkout) -> Bool {
        lhs.id == rhs.id &&
        lhs.kind == rhs.kind &&
        lhs.title == rhs.title &&
        lhs.distance == rhs.distance &&
        lhs.scheduledDate == rhs.scheduledDate &&
        lhs.intensity == rhs.intensity
    }
}

private struct FlexWeekDiffRow: View {
    var original: PlannedWorkout
    var updated: PlannedWorkout
    var rationale: String

    var body: some View {
        RunSmartPanel(cornerRadius: 20, padding: 16, accent: .accentPrimary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(FlexWeekPresentation.weekdayLabel(for: original.scheduledDate))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textTertiary)
                        Text("\(original.title) · \(original.distance)")
                            .font(.bodyMD)
                            .foregroundStyle(Color.textSecondary)
                            .strikethrough(true, color: Color.textTertiary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                    }
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.black))
                        .foregroundStyle(Color.accentPrimary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(FlexWeekPresentation.weekdayLabel(for: updated.scheduledDate))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentPrimary)
                        Text("\(updated.title) · \(updated.distance)")
                            .font(.bodyMD.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                    }
                }

                Text(rationale)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FlexWeekUnchangedRow: View {
    var workout: PlannedWorkout

    var body: some View {
        HStack(spacing: 12) {
            Text(FlexWeekPresentation.weekdayLabel(for: workout.scheduledDate))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 44, alignment: .leading)
            Text("\(workout.title) · \(workout.distance)")
                .font(.bodyMD)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#if DEBUG
#Preview("Flex Week Diff") {
    let week = RunSmartPreviewData.workouts
    let (updated, changes) = DeterministicFlexWeekBuilder.restructure(
        week: week,
        reason: .tired
    )
    FlexWeekDiffView(
        originalWeek: week,
        outcome: FlexWeekOutcome(
            restructuredWeek: updated,
            changes: changes,
            safetyWarnings: ["Weekly mileage stays within the 10% safety band."],
            source: .deterministicFallback
        ),
        isLoading: false,
        onCancel: {},
        onConfirm: {},
        onKeepOriginal: {}
    )
    .preferredColorScheme(.dark)
}
#endif
