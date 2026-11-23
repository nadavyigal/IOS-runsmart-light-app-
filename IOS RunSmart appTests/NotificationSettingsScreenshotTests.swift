import SwiftUI
import UIKit
import XCTest
@testable import IOS_RunSmart_app

/// C7.14: renders both settings screens with fixture data and writes PNGs. It does nothing unless
/// `TEST_RUNNER_COACH_NOTIF_SHOTS=<folder>` is set:
///
///     TEST_RUNNER_COACH_NOTIF_SHOTS=/tmp/coach-notif xcodebuild test ... -only-testing:"IOS RunSmart appTests/NotificationSettingsScreenshotTests"
@MainActor
final class NotificationSettingsScreenshotTests: XCTestCase {
    private nonisolated final class QuietAnalytics: AnalyticsTracking, @unchecked Sendable {
        func track(_ event: String, properties: [String: Any]) {}
        func identify(userId: String, traits: [String: Any]) {}
        func register(properties: [String: Any]) {}
        func unregister(_ key: String) {}
        func reset() {}
    }

    private func folder() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["COACH_NOTIF_SHOTS"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_COACH_NOTIF_SHOTS to write screenshots.")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func loadedModel(
        _ audience: NotificationSettingsAudience,
        permission: NotificationPermissionStatus = .granted,
        prefs: NotificationPrefs = NotificationPrefs(timeZone: "Asia/Jerusalem")
    ) async -> NotificationSettingsModel {
        let store = NotifFakeStore()
        store.row = prefs
        let model = NotificationSettingsModel(
            audience: audience, store: store, permissionFlow: NotifFakePermission(permission),
            analytics: { QuietAnalytics() }, timeZoneIdentifier: { "Asia/Jerusalem" }
        )
        await model.load(v2Enabled: true)
        return model
    }

    private func render(_ model: NotificationSettingsModel, name: String, height: CGFloat,
                        rtl: Bool = false, size: DynamicTypeSize = .large, to folder: URL) async throws {
        let content = NotificationSettingsScreen(model: model, v2Enabled: true, onDone: {})
            .frame(width: 390, height: height)
            .environment(\.locale, Locale(identifier: rtl ? "he_IL" : "en_GB"))
            .environment(\.dynamicTypeSize, size)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            .preferredColorScheme(.dark)

        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = UIColor(Color.surfaceBase)
        let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: 390, height: height)))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        // The screen's own load runs once more on appear; wait until it settles.
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            host.view.layoutIfNeeded()
            if model.loadState == .loaded { break }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("\(name).png"))
    }

    func testWriteScreenshots() async throws {
        executionTimeAllowance = 180
        let out = try folder()

        var changed = NotificationPrefs(timeZone: "Asia/Jerusalem")
        changed.coachEveningSummary = false

        // Coach T5.
        try await render(await loadedModel(.coach, prefs: changed), name: "01-coach-default", height: 820, to: out)
        try await render(await loadedModel(.coach, prefs: changed), name: "02-coach-xxxl", height: 1500,
                         size: .xxxLarge, to: out)
        try await render(await loadedModel(.coach, prefs: changed), name: "03-coach-ax3", height: 2200,
                         size: .accessibility3, to: out)
        try await render(await loadedModel(.coach, permission: .denied, prefs: changed),
                         name: "04-coach-permission-denied", height: 920, to: out)
        try await render(await loadedModel(.coach, permission: .notDetermined, prefs: changed),
                         name: "05-coach-never-prompted", height: 880, to: out)

        // Athlete, with an English and a Hebrew coach name.
        try await render(await loadedModel(.athlete(coachName: "Dana")), name: "06-athlete-default",
                         height: 820, to: out)
        try await render(await loadedModel(.athlete(coachName: "דנה כהן")), name: "07-athlete-hebrew-coach-name",
                         height: 820, to: out)
        try await render(await loadedModel(.athlete(coachName: "דנה כהן")), name: "08-athlete-rtl-layout",
                         height: 820, rtl: true, to: out)
        try await render(await loadedModel(.athlete(coachName: "Dana"), permission: .denied),
                         name: "09-athlete-permission-denied", height: 920, to: out)
        try await render(await loadedModel(.athlete(coachName: "Dana")), name: "10-athlete-xxxl", height: 1500,
                         size: .xxxLarge, to: out)

        // Equal quiet times: the line shows and Save is off.
        let equal = await loadedModel(.coach)
        equal.quietTo = equal.quietFrom
        try await render(equal, name: "11-coach-quiet-hours-equal", height: 860, to: out)

        // A failed save: the toggle goes back and the line shows.
        let failingStore = NotifFakeStore()
        failingStore.row = changed
        let failing = NotificationSettingsModel(
            audience: .coach, store: failingStore, permissionFlow: NotifFakePermission(.granted),
            analytics: { QuietAnalytics() }, timeZoneIdentifier: { "Asia/Jerusalem" })
        await failing.load(v2Enabled: true)
        failingStore.failUpdate = true
        await failing.setToggle(.coachRunFinished, to: false)
        try await render(failing, name: "12-coach-save-failed", height: 880, to: out)
    }
}
