import SwiftUI

/// C2. Two radios. Disabled, with "Set for the pilot", only after the save succeeds.
struct PlanModePickerView: View {
    @Binding var selection: CoachPlanMode?
    var locked: Bool
    var notice: String?
    var errorMessage: String?
    var isSaving: Bool
    var onContinue: () -> Void

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("How do you want to coach?")
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(CoachPlanMode.allCases, id: \.self) { mode in
                    Button {
                        selection = mode
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selection == mode ? "largecircle.fill.circle" : "circle")
                                .font(.bodyLG)
                                .foregroundStyle(selection == mode ? Color.accentPrimary : Color.textSecondary)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                    .font(.bodyLG.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                Text(mode.explanation)
                                    .font(.bodyMD)
                                    .foregroundStyle(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(locked)
                    .accessibilityIdentifier("coach-plan-mode-\(mode.rawValue)")
                }

                if locked {
                    Text(GroupPlanRules.lockedCaption)
                        .font(.bodyMD.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("coach-plan-mode-locked")
                } else if let notice {
                    Text(notice)
                        .font(.bodyMD)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("coach-plan-mode-notice")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.bodyMD)
                        .foregroundStyle(Color.accentHeart)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("coach-plan-mode-error")
                }

                if !locked {
                    Button(action: onContinue) {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.black)
                            }
                            Text("Continue")
                        }
                    }
                    .buttonStyle(NeonButtonStyle())
                    .disabled(selection == nil || isSaving)
                    .accessibilityIdentifier("coach-plan-mode-continue")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
