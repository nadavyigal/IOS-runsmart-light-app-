import SwiftUI
import UIKit
import XCTest
@preconcurrency import UserNotifications
@testable import IOS_RunSmart_app

/// C7.10: renders T6 (inside Coach Today), P10 and the tap notice and writes PNGs. It does nothing
/// unless `TEST_RUNNER_REMOTE_PUSH_SHOTS=<folder>` is set, so normal test runs skip it.
@MainActor
final class RemotePushScreenshotTests: XCTestCase {
    private struct NoRepository: RemotePushRepository {
        func register(token: String, environment: RemotePushEnvironment, bundleID: String?) async throws {}
        func unregister(token: String) async throws {}
        func prefs(timeZone: String) async throws -> RemoteNotificationPrefs {
            try JSONDecoder().decode(RemoteNotificationPrefs.self, from: Data(#"{"time_zone":"UTC"}"#.utf8))
        }
        func setTimeZone(_ timeZone: String) async throws {}
    }

    private struct UndecidedSystem: RemotePushSystem {
        func authorizationStatus() async -> UNAuthorizationStatus { .notDetermined }
        func requestAuthorization() async throws -> Bool { false }
        func registerForRemoteNotifications() {}
        func unregisterForRemoteNotifications() {}
    }

    private nonisolated final class NoAnalytics: AnalyticsTracking, @unchecked Sendable {
        func track(_ event: String, properties: [String: Any]) {}
        func identify(userId: String, traits: [String: Any]) {}
        func register(properties: [String: Any]) {}
        func unregister(_ key: String) {}
        func reset() {}
    }

    private func folder() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["REMOTE_PUSH_SHOTS"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_REMOTE_PUSH_SHOTS to write screenshots.")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func registrar() async -> RemotePushRegistrar {
        let registrar = RemotePushRegistrar(
            repository: NoRepository(), system: UndecidedSystem(),
            store: RemotePushStateStore(defaults: UserDefaults(suiteName: "RemotePushShots.\(UUID().uuidString)")!),
            analytics: { NoAnalytics() }
        )
        registrar.update(userID: UUID(), v2Enabled: true)
        await registrar.coachTodayOpened()
        await registrar.athleteConsentAcknowledged(coachName: "Dana Levi")
        return registrar
    }

    private func render<V: View>(_ view: V, name: String, height: CGFloat, size: DynamicTypeSize = .large, to folder: URL) throws {
        let content = view
            .frame(width: 390, height: height, alignment: .topLeading)
            .background(Color.surfaceBase)
            .environment(\.locale, Locale(identifier: "en_GB"))
            .environment(\.dynamicTypeSize, size)
            .preferredColorScheme(.dark)
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = UIColor(Color.surfaceBase)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: height))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("\(name).png"))
    }

    func testWriteScreenshots() async throws {
        let folder = try folder()
        let registrar = await registrar()
        XCTAssertTrue(registrar.showsCoachPrimer)
        let primer = try XCTUnwrap(registrar.athletePrimer)

        let model = CoachAthleteListModel.previewModel(.previewFixture(athletes: 6, withNews: true))
        let today = VStack(alignment: .leading, spacing: 14) {
            CoachTodayView(model: model, pushRegistrar: registrar, onShareInvite: {}, open: { _ in }, retry: {})
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        try render(today, name: "01-t6-coach-today", height: 900, to: folder)
        try render(
            RemotePushCoachPrimerCard(registrar: registrar).padding(18), name: "02-t6-card-xxxl",
            height: 520, size: .accessibility3, to: folder
        )
        try render(RemotePushAthletePrimerSheet(primer: primer, registrar: registrar), name: "03-p10", height: 420, to: folder)
        try render(
            RemotePushAthletePrimerSheet(primer: RemotePushAthletePrimer(coachName: "דנה לוי"), registrar: registrar),
            name: "04-p10-hebrew-name", height: 420, to: folder
        )
        registrar.tapNotice = RemotePushCopy.athleteGone("Dana Levi")
        try render(RemotePushNoticeHost(registrar: registrar), name: "05-gone-notice", height: 160, to: folder)
    }
}
