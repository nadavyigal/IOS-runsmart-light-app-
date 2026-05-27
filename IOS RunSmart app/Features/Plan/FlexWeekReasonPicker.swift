import SwiftUI

struct FlexWeekReasonPicker: View {
    var currentWeek: [PlannedWorkout]
    var readinessContext: ReadinessContext?
    var preselectedReason: FlexWeekReason?
    var showInterventionCard: Bool
    var onCancel: () -> Void
    var onContinue: (FlexWeekRequest) -> Void
    var onTalkToCoach: (() -> Void)?

    @State private var selectedKind: FlexWeekReasonKind?
    @State private var blockedDays: Set<Date> = []
    @State private var missedWorkoutID: UUID?
    @State private var sickDaysOut: Int?
    @State private var interventionDismissed = false

    private let weekDays: [Date]
    private let calendar: Calendar

    init(
        currentWeek: [PlannedWorkout],
        readinessContext: ReadinessContext? = nil,
        preselectedReason: FlexWeekReason? = nil,
        calendar: Calendar = .current,
        showInterventionCard: Bool = false,
        onCancel: @escaping () -> Void,
        onContinue: @escaping (FlexWeekRequest) -> Void,
        onTalkToCoach: (() -> Void)? = nil
    ) {
        self.currentWeek = currentWeek
        self.readinessContext = readinessContext
        self.preselectedReason = preselectedReason
        self.calendar = calendar
        self.showInterventionCard = showInterventionCard
        self.onCancel = onCancel
        self.onContinue = onContinue
        self.onTalkToCoach = onTalkToCoach
        self.weekDays = FlexWeekPresentation.currentWeekDays(calendar: calendar)

        _selectedKind = State(initialValue: preselectedReason?.kind)

        if case .traveling(let days)? = preselectedReason {
            _blockedDays = State(initialValue: Set(days.map { calendar.startOfDay(for: $0) }))
        }

        if case .missedWorkout(let id)? = preselectedReason {
            _missedWorkoutID = State(initialValue: id)
        }

        if case .sick(let daysOut)? = preselectedReason {
            _sickDaysOut = State(initialValue: daysOut)
        }
    }

    var body: some View {
        ZStack {
            RunSmartBackground(context: .plan)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    interventionSection
                    hero
                    reasonCards
                    detailSection
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 78)
                .padding(.bottom, 148)
            }

            topBar
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: hydrateDefaults)
    }

    @ViewBuilder
    private var interventionSection: some View {
        if showInterventionCard && !interventionDismissed {
            GentleCoachInterventionCard(
                onTalkToCoach: {
                    interventionDismissed = true
                    onTalkToCoach?()
                },
                onContinue: {
                    interventionDismissed = true
                }
            )
        }
    }

    private func handleCancel() {
        if showInterventionCard && !interventionDismissed {
            RunSmartAnalytics.flexWeekInterventionAction(.cancelled)
        }
        onCancel()
    }

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: handleCancel) {
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
                    Text("Adjust Your Week")
                        .font(.bodyMD.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Tell Coach what changed")
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
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Flex Week")
                Text("Pick what’s going on and Coach will rewrite the rest of this week with a clear rationale for every change.")
                    .font(.bodyLG)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let evidence = readinessContext?.tiredEvidence, selectedKind == .tired {
                    Text(evidence)
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.accentRecovery)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var reasonCards: some View {
        VStack(spacing: 12) {
            ForEach(FlexWeekReasonKind.allCases, id: \.self) { kind in
                FlexWeekReasonCard(
                    kind: kind,
                    selected: selectedKind == kind,
                    subtitle: subtitle(for: kind)
                ) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        select(kind)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailSection: some View {
        switch selectedKind {
        case .traveling:
            travelingDayPicker
        case .missedWorkout:
            missedWorkoutChip
        case .sick:
            sickDayPicker
        default:
            EmptyView()
        }
    }

    private var travelingDayPicker: some View {
        RunSmartPanel(cornerRadius: 20, padding: 16, accent: .accentEnergy) {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "Which days are blocked?")
                Text("Coach will mark these as rest and shift key workouts when it’s safe.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(weekDays, id: \.self) { day in
                        let normalized = calendar.startOfDay(for: day)
                        let selected = blockedDays.contains(normalized)
                        Button {
                            toggleBlockedDay(normalized)
                        } label: {
                            VStack(spacing: 4) {
                                Text(FlexWeekPresentation.weekdayLabel(for: day, calendar: calendar))
                                    .font(.caption.weight(.bold))
                                Text(dayNumber(for: day))
                                    .font(.bodyMD.weight(.semibold))
                            }
                            .foregroundStyle(selected ? Color.black : Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selected ? Color.accentPrimary : Color.surfaceCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(selected ? Color.accentPrimary : Color.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(FlexWeekPresentation.weekdayLabel(for: day, calendar: calendar)), \(selected ? "selected" : "not selected")")
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var missedWorkoutChip: some View {
        Group {
            if let workout = selectedMissedWorkout {
                RunSmartPanel(cornerRadius: 18, padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Missed workout")
                        HStack(spacing: 10) {
                            Image(systemName: "figure.run")
                                .font(.bodyMD.weight(.bold))
                                .foregroundStyle(Color.accentPrimary)
                            Text(FlexWeekPresentation.missedWorkoutChipLabel(workout))
                                .font(.bodyMD.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.78)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.surfaceCard.opacity(0.72), in: Capsule())
                        .overlay(Capsule().stroke(Color.border, lineWidth: 1))
                    }
                }
            } else {
                RunSmartPanel(cornerRadius: 18, padding: 14) {
                    Text("No missed workouts found in this week.")
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var sickDayPicker: some View {
        RunSmartPanel(cornerRadius: 20, padding: 16, accent: .accentRecovery) {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "How many days do you think?")
                Text("Coach will rest you through recovery and ease you back with an easy return run.")
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    ForEach(sickDayOptions, id: \.label) { option in
                        Button {
                            sickDaysOut = option.daysOut
                        } label: {
                            Text(option.label)
                                .font(.labelSM)
                                .tracking(0.8)
                                .foregroundStyle(sickDaysOut == option.daysOut ? Color.black : Color.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(sickDaysOut == option.daysOut ? Color.accentPrimary : Color.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button(action: submit) {
                Text("Continue")
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(!canContinue)

            Button(action: onCancel) {
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

    private var canContinue: Bool {
        guard let reason = resolvedReason else { return false }
        return FlexWeekPresentation.isValid(reason, week: currentWeek)
    }

    private var resolvedReason: FlexWeekReason? {
        guard let selectedKind else { return nil }
        switch selectedKind {
        case .tired:
            return .tired
        case .traveling:
            return .traveling(blockedDays: blockedDays.sorted())
        case .missedWorkout:
            guard let missedWorkoutID else { return nil }
            return .missedWorkout(workoutID: missedWorkoutID)
        case .sick:
            return .sick(daysOut: sickDaysOut)
        }
    }

    private var selectedMissedWorkout: PlannedWorkout? {
        guard let missedWorkoutID else { return nil }
        return FlexWeekPresentation.workout(in: currentWeek, id: missedWorkoutID)
    }

    private var sickDayOptions: [(label: String, daysOut: Int?)] {
        [
            ("3 days", 3),
            ("5 days", 5),
            ("7 days", 7),
            ("Not sure", nil)
        ]
    }

    private func subtitle(for kind: FlexWeekReasonKind) -> String {
        switch kind {
        case .tired:
            return readinessContext?.tiredEvidence ?? "Ease today and protect the rest of the week."
        case .traveling:
            return "Block travel days and keep mileage safe."
        case .missedWorkout:
            if let workout = selectedMissedWorkout ?? FlexWeekPresentation.mostRecentMissedWorkout(in: currentWeek, calendar: calendar) {
                return "Reschedule \(workout.title.lowercased()) without doubling up."
            }
            return "Pick up where you left off without overdoing it."
        case .sick:
            return "Rest through illness and return with an easy test run."
        }
    }

    private func hydrateDefaults() {
        if missedWorkoutID == nil,
           preselectedReason == nil || preselectedReason?.kind == .missedWorkout,
           let missed = FlexWeekPresentation.mostRecentMissedWorkout(in: currentWeek, calendar: calendar) {
            missedWorkoutID = missed.id
        }

        if selectedKind == nil, let preselectedReason {
            selectedKind = preselectedReason.kind
        }

        if sickDaysOut == nil, selectedKind == .sick {
            sickDaysOut = nil
        }
    }

    private func select(_ kind: FlexWeekReasonKind) {
        selectedKind = kind
        switch kind {
        case .missedWorkout:
            if missedWorkoutID == nil,
               let missed = FlexWeekPresentation.mostRecentMissedWorkout(in: currentWeek, calendar: calendar) {
                missedWorkoutID = missed.id
            }
        case .sick where sickDaysOut == nil:
            sickDaysOut = nil
        default:
            break
        }
    }

    private func toggleBlockedDay(_ day: Date) {
        if blockedDays.contains(day) {
            blockedDays.remove(day)
        } else {
            blockedDays.insert(day)
        }
    }

    private func dayNumber(for date: Date) -> String {
        String(calendar.component(.day, from: date))
    }

    private func submit() {
        guard let reason = resolvedReason else { return }
        RunSmartHaptics.light()
        onContinue(
            FlexWeekRequest(
                reason: reason,
                currentWeek: currentWeek,
                readinessContext: readinessContext
            )
        )
    }
}

private struct FlexWeekReasonCard: View {
    var kind: FlexWeekReasonKind
    var selected: Bool
    var subtitle: String
    var onTap: () -> Void

    private var title: String {
        switch kind {
        case .tired: "I'm tired"
        case .traveling: "I'm traveling"
        case .missedWorkout: "I missed a workout"
        case .sick: "I'm sick"
        }
    }

    private var symbol: String {
        switch kind {
        case .tired: "battery.25"
        case .traveling: "airplane"
        case .missedWorkout: "calendar.badge.exclamationmark"
        case .sick: "heart.text.square"
        }
    }

    private var tint: Color {
        switch kind {
        case .tired: .accentRecovery
        case .traveling: .accentEnergy
        case .missedWorkout: .accentMagenta
        case .sick: .accentHeart
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(0.16))
                        .frame(width: 52, height: 52)
                        .shadow(color: tint.opacity(selected ? 0.45 : 0.20), radius: selected ? 16 : 8)
                    Image(systemName: selected ? "checkmark" : symbol)
                        .font(.title3.weight(.black))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headingMD.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                    Text(subtitle)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selected ? Color.accentPrimary : Color.textTertiary)
                    .padding(.top, 6)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.10) : Color.surfaceElevated.opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selected ? Color.accentPrimary : Color.border, lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Flex Week Reason Picker") {
    FlexWeekReasonPicker(
        currentWeek: RunSmartPreviewData.workouts,
        readinessContext: ReadinessContext.make(
            recovery: RunSmartPreviewData.recovery,
            recommendation: RunSmartPreviewData.today
        ),
        onCancel: {},
        onContinue: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Flex Week Reason Picker — Missed Preselect") {
    let missed = FlexWeekPresentation.mostRecentMissedWorkout(in: RunSmartPreviewData.workouts) ?? RunSmartPreviewData.workouts[0]
    FlexWeekReasonPicker(
        currentWeek: RunSmartPreviewData.workouts,
        preselectedReason: .missedWorkout(workoutID: missed.id),
        onCancel: {},
        onContinue: { _ in }
    )
    .preferredColorScheme(.dark)
}
#endif
