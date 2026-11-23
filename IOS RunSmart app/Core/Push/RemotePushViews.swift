import SwiftUI

// C7.10 pre-permission surfaces and the tap notice. Exact copy: UX spec §A.6 (T6), §C.5 (P10).
// "Turn on" and "Not now" are the same size with no pressure styling, like P8 and P9.

/// T6: the coach's push pre-permission card, under the Coach Today header.
struct RemotePushCoachPrimerCard: View {
    @ObservedObject var registrar: RemotePushRegistrar

    var body: some View {
        ContentCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(RemotePushCopy.coachPrimerTitle)
                    .font(.headingMD)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(RemotePushCopy.coachPrimerBody)
                    .font(.bodyMD)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                RemotePushPrimerButtons(isWorking: registrar.isWorking) {
                    Task { await registrar.turnOn(.coach) }
                } notNow: {
                    registrar.notNow(.coach)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("remote-push-coach-primer")
    }
}

/// P10: the athlete's push pre-permission, shown after P8 or P9 OK.
struct RemotePushAthletePrimerSheet: View {
    let primer: RemotePushAthletePrimer
    @ObservedObject var registrar: RemotePushRegistrar

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: RemotePushCopy.athletePrimerTitle(coach: primer.coachName))
                    .font(.displayMD)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: RemotePushCopy.athletePrimerBody(coach: primer.coachName))
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                RemotePushPrimerButtons(isWorking: registrar.isWorking) {
                    Task { await registrar.turnOn(.athlete) }
                } notNow: {
                    registrar.notNow(.athlete)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(registrar.isWorking)
        .accessibilityIdentifier("remote-push-athlete-primer")
    }
}

private struct RemotePushPrimerButtons: View {
    let isWorking: Bool
    let turnOn: () -> Void
    let notNow: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Accessibility text sizes stack the buttons so neither label is squeezed.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) { buttons }
        } else {
            HStack(spacing: 12) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        button(RemotePushCopy.turnOn, showsProgress: isWorking, action: turnOn)
        button(RemotePushCopy.notNow, showsProgress: false, action: notNow)
    }

    private func button(_ title: String, showsProgress: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if showsProgress {
                    ProgressView()
                } else {
                    Text(verbatim: title)
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.textPrimary)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))
        .disabled(isWorking)
        .accessibilityLabel(title)
    }
}

extension View {
    /// P10 host. Attach to Today, next to `coachConsentNotice()`. Renders nothing while the
    /// registrar has no athlete primer, which is always the case with v2 off.
    func remotePushAthletePrimer(_ registrar: RemotePushRegistrar = .shared) -> some View {
        modifier(RemotePushAthletePrimerHost(registrar: registrar))
    }
}

private struct RemotePushAthletePrimerHost: ViewModifier {
    @ObservedObject var registrar: RemotePushRegistrar
    /// The sheet waits for P9's sheet or the join sheet to finish closing.
    @State private var presented: RemotePushAthletePrimer?

    func body(content: Content) -> some View {
        content
            .task(id: registrar.athletePrimer) {
                guard let primer = registrar.athletePrimer else {
                    presented = nil
                    return
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled, registrar.athletePrimer == primer else { return }
                presented = primer
            }
            .sheet(item: Binding(
                get: { presented },
                set: { value in
                    // A swipe-away counts as "Not now": no system prompt, never shown again.
                    if value == nil, presented != nil, registrar.athletePrimer != nil {
                        registrar.notNow(.athlete)
                    }
                    presented = value
                }
            )) { primer in
                RemotePushAthletePrimerSheet(primer: primer, registrar: registrar)
            }
    }
}

/// AC8: the one-line notice after a tapped push whose target is gone. Shown at the top for 4 s.
struct RemotePushNoticeHost: View {
    @ObservedObject var registrar: RemotePushRegistrar

    var body: some View {
        if let notice = registrar.tapNotice {
            VStack {
                Text(verbatim: notice)
                    .font(.bodyMD.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.border, lineWidth: 1))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityIdentifier("remote-push-notice")
                    .onTapGesture { registrar.tapNotice = nil }
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: notice) {
                UIAccessibility.post(notification: .announcement, argument: notice)
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled, registrar.tapNotice == notice else { return }
                withAnimation(.easeInOut(duration: 0.24)) { registrar.tapNotice = nil }
            }
        }
    }
}
