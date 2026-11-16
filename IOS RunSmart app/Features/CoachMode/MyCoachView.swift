import Network
import SwiftUI

/// A11 My coach, and A13 leave confirm. Human coach only.
struct MyCoachView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SupabaseSession
    @EnvironmentObject private var coachLinks: CoachLinkStore

    @StateObject private var model = LeaveCoachModel()
    @State private var showLeaveSheet = false
    @State private var pathMonitor: NWPathMonitor?

    var body: some View {
        Group {
            if let link = coachLinks.currentLink {
                coach(link)
            } else {
                Text("Join a coach")
                    .font(.body.weight(.semibold))
            }
        }
        .onAppear(perform: startReachability)
        .onDisappear(perform: stopReachability)
        .sheet(isPresented: $showLeaveSheet) {
            if let link = coachLinks.currentLink {
                LeaveCoachSheet(coachName: link.coachName, model: model) {
                    guard let userID = session.currentUserID else { return }
                    let toast = await model.confirm(
                        coachName: link.coachName,
                        userID: userID,
                        store: coachLinks,
                        expectedLinkID: link.id
                    )
                    if toast != nil {
                        showLeaveSheet = false
                        dismiss()
                    }
                }
            }
        }
    }

    private func coach(_ link: CoachLink) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Text(LeaveCoachCopy.monogram(for: link.coachName))
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.surfaceElevated, in: Circle())
                    .accessibilityLabel("\(link.coachName) avatar")
                Text(link.coachName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What \(link.coachName) can see")
                    .font(.headline)
                ForEach(CoachConsentCopy.sharedBullets(), id: \.self) { bullet in
                    Text("• \(bullet)")
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Story 6.1 adds the route-sharing toggle here.
            // Story 3.2 adds the Feedback list here.

            Button("Leave coach") {
                model.cancel()
                showLeaveSheet = true
            }
            .buttonStyle(NeonButtonStyle(isDestructive: true))
            .disabled(model.leaveDisabledReason != nil)
            .accessibilityLabel("Leave coach")

            if let reason = model.leaveDisabledReason {
                Text(reason)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startReachability() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in
                model.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "leave-coach-path"))
        pathMonitor = monitor
    }

    private func stopReachability() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }
}

/// A13. Equal-weight buttons, no timer, no second confirmation.
private struct LeaveCoachSheet: View {
    var coachName: String
    @ObservedObject var model: LeaveCoachModel
    var onConfirm: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            content
                .padding(20)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(model.isWorking)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LeaveCoachCopy.sheet(coach: coachName))
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = model.isOnline ? model.errorMessage : LeaveCoachCopy.offline {
                Text(errorMessage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentAmber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    model.cancel()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .disabled(model.isWorking)
                .frame(maxWidth: .infinity)

                Button {
                    Task { await onConfirm() }
                } label: {
                    if model.isWorking {
                        ProgressView()
                    } else {
                        Text("Leave \(coachName)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(maxWidth: .infinity)
                .disabled(!model.isOnline || model.isWorking)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
