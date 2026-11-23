import SwiftUI
import UIKit

/// Coach tab root. Plan Mode (C2) is a hard gate in front of the invite (C4).
struct CoachTabView: View {
    @StateObject private var model: CoachPlanSetupModel

    @State private var showsWelcomeEditor = false
    @State private var showsWelcomeHint = false
    /// C7.1: Today rows open the athlete from code, so the analytics event fires for a tap and for VoiceOver alike.
    @State private var path = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase

    private let welcomeService = SupabaseCoachWelcomeService()
    private let welcomeHint = CoachWelcomeHint()

    let ownerID: UUID
    @ObservedObject var athletes: CoachAthleteListModel

    init(ownerID: UUID, athletes: CoachAthleteListModel,
         repository: any CoachPlanRepository = SupabaseCoachPlanRepository()) {
        self.ownerID = ownerID
        self.athletes = athletes
        _model = StateObject(wrappedValue: CoachPlanSetupModel(repository: repository))
    }

    var body: some View {
        if RunSmartFeatures.coachModeEnabled {
            NavigationStack(path: $path) {
                coachScreen
                    .navigationDestination(for: CoachAthleteDestination.self) { athlete in
                        // C7.11: a removed athlete leaves the roster as soon as the detail closes.
                        CoachAthleteDetailView(destination: athlete, onRemoved: {
                            Task { await athletes.refresh(owner: ownerID) }
                        })
                            // C7.2: opening the detail marks the athlete seen, from Today or the roster.
                            // `markSeen` does nothing unless v2 is on.
                            .onAppear { if athlete.coachV2 { athletes.markSeen(athlete.athleteID) } }
                    }
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    private var coachScreen: some View {
        ScrollViewReader { proxy in
            coachContent(scrollTo: proxy)
        }
    }

    private func openToday(_ destination: CoachAthleteDestination, _ row: CoachTodayRow) {
        athletes.trackRowOpened(row)
        path.append(destination)
    }

    private func coachContent(scrollTo proxy: ScrollViewProxy) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                if showsWelcomeHint {
                    ContentCard {
                        Button(action: openWelcomeEditor) {
                            Label("Add a welcome for new athletes", systemImage: "hand.wave")
                                .font(.bodyMD.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentPrimary)
                    }
                }

                if model.loadFailed {
                    loadFailure
                    if athletes.ownerID == ownerID, athletes.updatedAt != nil {
                        CoachAthleteList(
                            model: athletes, ownerID: ownerID, planSetupUnavailable: true, open: openToday,
                            onShareInvite: { withAnimation { proxy.scrollTo("coach-invite", anchor: .top) } }
                        ) {
                            await athletes.refresh(owner: ownerID)
                        }
                    }
                } else if !model.didLoad {
                    ProgressView()
                        .tint(Color.accentPrimary)
                        .frame(maxWidth: .infinity, minHeight: 96)
                        .accessibilityLabel("Loading Plan Mode")
                } else {
                    if model.showsLockedMode {
                        PlanModePickerView(
                            selection: .constant(model.mode),
                            locked: true,
                            notice: nil,
                            errorMessage: nil,
                            isSaving: false,
                            onContinue: {}
                        )
                    } else {
                        PlanModePickerView(
                            selection: $model.pendingMode,
                            locked: false,
                            notice: GroupPlanRules.pilotNotice,
                            errorMessage: model.choiceError,
                            isSaving: model.isSavingChoice,
                            onContinue: { Task { await model.confirmChoice() } }
                        )
                    }

                    if model.showsGroupForm {
                        GroupPlanSettingsView(
                            initial: model.groupPlan,
                            savedMessage: model.savedMessage,
                            failureMessage: model.settingsError,
                            isSaving: model.isSavingSettings,
                            onSave: { settings in Task { await model.saveSettings(settings) } }
                        )
                        .id(model.groupPlan?.raceDateString() ?? "new-group-plan")
                    }

                    if model.showsInvite {
                        CoachAthleteList(
                            model: athletes, ownerID: ownerID, open: openToday,
                            onShareInvite: { withAnimation { proxy.scrollTo("coach-invite", anchor: .top) } }
                        ) {
                            await athletes.refresh(owner: ownerID)
                        }
                        CoachInviteSection().id("coach-invite")
                    }

                    if let savedMessage = model.savedMessage, model.showsInvite {
                        Text(savedMessage)
                            .font(.bodyMD.weight(.semibold))
                            .foregroundStyle(Color.accentSuccess)
                            .accessibilityIdentifier("coach-group-plan-saved")
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 140)
        }
        .task { await model.load() }
        .task {
            if let settings = try? await welcomeService.settings(athleteID: nil), !Task.isCancelled {
                showsWelcomeHint = welcomeHint.shouldShow(ownerID: ownerID, savedText: settings.savedText)
            }
        }
        .sheet(isPresented: $showsWelcomeEditor) {
            CoachWelcomeEditor(service: welcomeService)
        }
        .task(id: model.showsInvite) {
            if model.showsInvite { await athletes.refresh(owner: ownerID) }
        }
        .refreshable {
            if model.showsInvite { await athletes.refresh(owner: ownerID) }
        }
        // C7.1. Everything below does nothing unless Coach Today is on (`athletes.coachV2 == .on`).
        .onChange(of: scenePhase) { _, phase in
            // Back from the background: refresh and show it. Flag-off keeps the 1.2.6 behavior.
            if phase == .active, athletes.coachV2 == .on, model.showsInvite {
                Task { await athletes.refresh(owner: ownerID) }
            }
        }
        .task(id: athletes.coachV2) {
            // While Today is on screen, check for news every 5 minutes. A result that would move rows
            // waits behind the "New updates · Refresh" pill (UX spec A.3 item 7).
            guard athletes.coachV2 == .on else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled, model.showsInvite else { continue }
                await athletes.refresh(owner: ownerID, style: .quiet)
            }
        }
        .onChange(of: athletes.today?.generatedAt) { _, _ in athletes.trackTodayViewed() }
        .onAppear { athletes.trackTodayViewed() }
        .onDisappear { athletes.todayDidDisappear() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RunSmartTopBar(title: "Coach")
            Menu {
                if model.showsGroupMenu {
                    Button("Group plan settings") { model.openGroupSettings() }
                }
                Button("Welcome note", action: openWelcomeEditor)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Coach menu")
            .accessibilityIdentifier("coach-tab-menu")
        }
    }

    private func openWelcomeEditor() {
        welcomeHint.consume(ownerID: ownerID)
        showsWelcomeHint = false
        showsWelcomeEditor = true
    }

    private var loadFailure: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Couldn't load Plan Mode.")
                    .font(.bodyLG)
                    .foregroundStyle(Color.textPrimary)
                Button("Retry") { Task { await model.load() } }
                    .buttonStyle(NeonButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Invite section (UX spec C4): the code, a share link, Copy code, Copy link and Share.
struct CoachInviteSection: View {
    @StateObject private var viewModel: CoachInviteViewModel
    @State private var copiedLabel: String?

    init(repository: any CoachModeRepository = SupabaseCoachModeRepository()) {
        _viewModel = StateObject(wrappedValue: CoachInviteViewModel(repository: repository))
    }

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 14) {
                // Sentence case, no tracking: the spec bans all-caps labels (Hebrew has none).
                Text("Invite")
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                switch viewModel.state {
                case .loading:
                    ProgressView()
                        .tint(Color.accentPrimary)
                        .frame(maxWidth: .infinity, minHeight: 96)
                        .accessibilityLabel("Loading your invite")
                case .loaded(let invite):
                    loaded(invite)
                case .failed:
                    failed
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await viewModel.load() }
    }

    private func loaded(_ invite: CoachInvite) -> some View {
        let link = invite.link()
        return VStack(alignment: .leading, spacing: 14) {
            // The code is an LTR, letter-spaced block so it reads aloud and in RTL layouts the same way.
            Text(invite.code)
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .tracking(10)
                .foregroundStyle(Color.accentPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .environment(\.layoutDirection, .leftToRight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Invite code \(invite.code.map(String.init).joined(separator: " "))")
                .accessibilityIdentifier("coach-invite-code")

            Text(link.absoluteString)
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
                .environment(\.layoutDirection, .leftToRight)
                .textSelection(.enabled)
                .accessibilityIdentifier("coach-invite-link")

            HStack(spacing: 10) {
                copyButton("Copy code", copied: "Code copied", value: invite.code)
                copyButton("Copy link", copied: "Link copied", value: link.absoluteString)
            }

            ShareLink(item: invite.shareMessage()) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(NeonButtonStyle())
            .accessibilityIdentifier("coach-invite-share")

            // Always present so the layout doesn't jump; read aloud when it changes.
            Text(copiedLabel ?? " ")
                .font(.labelLG)
                .foregroundStyle(Color.accentSuccess)
                .accessibilityHidden(copiedLabel == nil)
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Couldn't load your invite.")
                .font(.bodyLG)
                .foregroundStyle(Color.textPrimary)
            Button("Retry") {
                Task { await viewModel.load() }
            }
            .buttonStyle(NeonButtonStyle())
            .accessibilityIdentifier("coach-invite-retry")
        }
    }

    private func copyButton(_ title: String, copied: String, value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            RunSmartHaptics.light()
            copiedLabel = copied
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if copiedLabel == copied { copiedLabel = nil }
            }
        } label: {
            Text(title)
                .font(.buttonLabel)
                .foregroundStyle(Color.accentPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: RunSmartRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: RunSmartRadius.md, style: .continuous)
                        .stroke(Color.accentPrimary.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
