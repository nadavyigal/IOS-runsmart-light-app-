import SwiftUI

/// Connect, disconnect and the auto-upload setting. Opened from the Profile "Connected" list,
/// which hides the Strava row entirely when the build has no Strava client id.
struct StravaConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SupabaseSession
    @ObservedObject private var strava = StravaConnectionService.shared
    @ObservedObject private var uploads = StravaUploadCoordinator.shared

    private var availability: StravaAvailability {
        strava.availability(isSignedIn: session.isAuthenticated)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    RunSmartPanel(cornerRadius: 20, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(title: "Strava")
                            content
                        }
                    }

                    if let message = strava.lastMessage {
                        Label(message, systemImage: "exclamationmark.circle.fill")
                            .font(.bodyMD)
                            .foregroundStyle(Color.accentEnergy)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("RunSmart sends the run you recorded, with its route, title and notes. Runs imported from Garmin or Apple Health are not sent.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.black.opacity(0.52).ignoresSafeArea())
            .navigationTitle("Strava")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch availability {
        case .hidden:
            Text("Strava is not set up in this build.")
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
        case .signInRequired:
            Text("Sign in to connect Strava.")
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
        case .available:
            if strava.isConnected {
                connectedContent
            } else {
                disconnectedContent
            }
        }
    }

    private var disconnectedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send your RunSmart runs to Strava with their route.")
                .font(.bodyMD)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await strava.connect() }
            } label: {
                if strava.isWorking {
                    ProgressView().tint(.black)
                } else {
                    Text("Connect Strava")
                }
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(strava.isWorking)
            .accessibilityHint("Opens Strava to approve RunSmart.")
        }
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(strava.connectedAthleteName.map { "Connected as \($0)" } ?? "Connected")
                .font(.bodyMD.weight(.semibold))
                .foregroundStyle(Color.accentPrimary)

            Toggle(isOn: $uploads.autoUploadEnabled) {
                Text("Upload new runs to Strava automatically")
                    .font(.bodyMD)
                    .foregroundStyle(Color.textPrimary)
            }
            .tint(Color.accentPrimary)

            Button(role: .destructive) {
                Task { await strava.disconnect() }
            } label: {
                Text("Disconnect")
                    .font(.buttonLabel)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentHeart)
            .disabled(strava.isWorking)
            .accessibilityHint("Removes the Strava connection from this phone and revokes RunSmart's access.")
        }
    }
}
