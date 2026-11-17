import SwiftUI

/// C3. Pickers stay inside the values the plan generator accepts.
struct GroupPlanSettingsView: View {
    @State private var settings: GroupPlanSettings
    var savedMessage: String?
    var failureMessage: String?
    var isSaving: Bool
    var onSave: (GroupPlanSettings) -> Void

    init(
        initial: GroupPlanSettings?,
        savedMessage: String?,
        failureMessage: String?,
        isSaving: Bool,
        onSave: @escaping (GroupPlanSettings) -> Void
    ) {
        _settings = State(initialValue: initial ?? GroupPlanRules.suggestedDefault())
        self.savedMessage = savedMessage
        self.failureMessage = failureMessage
        self.isSaving = isSaving
        self.onSave = onSave
    }

    private var dateNotice: GroupPlanRules.DateNotice? {
        GroupPlanRules.dateNotice(raceDate: settings.raceDate, targetDistance: settings.targetDistance)
    }

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Group plan settings")
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(GroupPlanRules.joinerHint)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                menuPicker("Goal", selection: $settings.goal, options: GroupPlanRules.goals, title: GroupPlanRules.goalTitle)
                menuPicker("Target distance", selection: $settings.targetDistance, options: GroupPlanRules.targetDistances, title: GroupPlanRules.distanceTitle)
                menuPicker("Level", selection: $settings.level, options: GroupPlanRules.levels, title: GroupPlanRules.levelTitle)

                Picker("Runs per week", selection: $settings.runsPerWeek) {
                    ForEach(Array(GroupPlanRules.runsPerWeek), id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("coach-group-plan-runs")

                DatePicker("Race date", selection: $settings.raceDate, displayedComponents: .date)
                    .accessibilityIdentifier("coach-group-plan-date")

                if let dateNotice, dateNotice.blocksSave {
                    Text(dateNotice.message)
                        .font(.bodyMD)
                        .foregroundStyle(Color.accentHeart)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("coach-group-plan-date-error")
                } else if dateNotice == .coversFinal16Weeks {
                    Text(GroupPlanRules.final16WeeksMessage)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("coach-group-plan-16-weeks")
                }

                if let savedMessage {
                    Text(savedMessage)
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.accentSuccess)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("coach-group-plan-saved")
                }

                if let failureMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(failureMessage)
                            .font(.bodyMD)
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Retry") { onSave(settings) }
                            .buttonStyle(NeonButtonStyle())
                            .disabled(isSaving)
                            .accessibilityIdentifier("coach-group-plan-retry")
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentHeart.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("coach-group-plan-failure")
                }

                Button {
                    onSave(settings)
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                        }
                        Text("Save")
                    }
                }
                .buttonStyle(NeonButtonStyle())
                .disabled(isSaving || dateNotice?.blocksSave == true)
                .accessibilityIdentifier("coach-group-plan-save")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func menuPicker(
        _ label: String,
        selection: Binding<String>,
        options: [String],
        title: @escaping (String) -> String
    ) -> some View {
        Picker(label, selection: selection) {
            ForEach(options, id: \.self) { option in
                Text(title(option)).tag(option)
            }
        }
        .pickerStyle(.menu)
    }
}
