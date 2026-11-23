import SwiftUI
import UIKit
import XCTest
@testable import IOS_RunSmart_app

/// C7.11: renders the coach's remove sheet and the athlete's one-time line with fixture data
/// and writes PNGs. It does nothing unless `TEST_RUNNER_COACH_REMOVE_SHOTS=<folder>` is set:
///
///     TEST_RUNNER_COACH_REMOVE_SHOTS=/tmp/coach-remove xcodebuild test ... -only-testing:"IOS RunSmart appTests/CoachLinkEndScreenshotTests"
@MainActor
final class CoachLinkEndScreenshotTests: XCTestCase {
    private nonisolated final class FailingService: CoachLinkEndServing, @unchecked Sendable {
        func removeAthlete(_ athleteID: UUID) async throws -> CoachRemoveOutcome { throw URLError(.timedOut) }
        func linkNotice() async throws -> CoachLinkNotice? { nil }
        func markLinkNoticeSeen(linkID: UUID) async throws {}
    }

    private func folder() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["COACH_REMOVE_SHOTS"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_COACH_REMOVE_SHOTS to write screenshots.")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func render<V: View>(_ view: V, name: String, height: CGFloat, rtl: Bool = false,
                                 size: DynamicTypeSize = .large, to folder: URL) throws {
        let content = view
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .frame(width: 390, height: height, alignment: .topLeading)
            .background(Color.surfaceBase)
            .environment(\.locale, Locale(identifier: "en_GB"))
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent("\(name).png"))
    }

    private func sheet(_ name: String, model: RemoveAthleteModel) -> some View {
        RemoveAthleteSheetContent(athleteName: name, model: model, onCancel: {}, onConfirm: {})
    }

    func testWriteScreenshots() async throws {
        executionTimeAllowance = 120
        let out = try folder()

        try render(sheet("Bea Levi", model: RemoveAthleteModel()), name: "01-remove-sheet", height: 760, to: out)
        try render(sheet("יוני כהן", model: RemoveAthleteModel()), name: "02-remove-sheet-hebrew-name",
                   height: 760, to: out)

        let failing = RemoveAthleteModel(service: FailingService(), analytics: { NoAnalytics() })
        _ = await failing.confirm(athleteID: UUID(), athleteName: "Bea Levi")
        try render(sheet("Bea Levi", model: failing), name: "03-remove-failed-still-linked", height: 820, to: out)

        try render(sheet("Bea Levi", model: RemoveAthleteModel(isOnline: false)), name: "04-remove-offline",
                   height: 820, to: out)
        try render(sheet("Bea Levi", model: RemoveAthleteModel()), name: "05-remove-sheet-xxxl",
                   height: 1300, size: .xxxLarge, to: out)

        let notice = CoachLinkNoticeCard(notice: CoachLinkNotice(linkID: UUID(), coachName: "Dana")) {}
        try render(notice, name: "06-athlete-notice", height: 220, to: out)
        let hebrewNotice = CoachLinkNoticeCard(notice: CoachLinkNotice(linkID: UUID(), coachName: "דנה")) {}
        try render(hebrewNotice, name: "07-athlete-notice-hebrew-coach", height: 220, to: out)
        try render(notice, name: "08-athlete-notice-rtl-layout", height: 220, rtl: true, to: out)
    }

    private nonisolated final class NoAnalytics: AnalyticsTracking, @unchecked Sendable {
        func track(_ event: String, properties: [String: Any]) {}
        func identify(userId: String, traits: [String: Any]) {}
        func register(properties: [String: Any]) {}
        func unregister(_ key: String) {}
        func reset() {}
    }
}
