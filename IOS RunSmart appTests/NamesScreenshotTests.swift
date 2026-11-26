import SwiftUI
import UIKit
import XCTest
@testable import IOS_RunSmart_app

/// Names fix (2026-11-26): Coach Today with named, Hebrew and unnamed athletes, the coach-name
/// card and the runner-name card. Writes PNGs only when `TEST_RUNNER_NAMES_SHOTS=<folder>` is set.
@MainActor
final class NamesScreenshotTests: XCTestCase {
    private func folder() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["NAMES_SHOTS"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_NAMES_SHOTS to write screenshots.")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func render<V: View>(
        _ view: V, name: String, size: DynamicTypeSize = .large, rtl: Bool = false,
        height: CGFloat, to folder: URL
    ) throws {
        let content = view
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
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

    /// Two named athletes (one Hebrew) and two who never set a name, as the roster RPC sends them.
    static func roster() -> CoachTodaySnapshot {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let zone = TimeZone(identifier: "Asia/Jerusalem")!
        let week = CoachAthleteWeek(now: now, locale: Locale(identifier: "en_GB"), timeZone: zone)
        let raw: [(String, Double)] = [("Noa", 40), ("נועה כהן", 30), ("Athlete", 12), ("RunSmart Runner", 3)]
        let athletes = raw.enumerated().map { index, entry in
            CoachAthleteSummary(
                athleteID: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!,
                displayName: entry.0, linkedAt: now.addingTimeInterval(-86_400 * entry.1), hasActivePlan: false
            )
        }
        let labeled = CoachAthleteNames.labeled(athletes, locale: Locale(identifier: "en_US"), timeZone: zone)
        return CoachTodaySnapshot.make(
            athletes: labeled, workouts: [], runs: [], now: now, week: week, locale: Locale(identifier: "en_GB")
        )
    }

    func testWriteScreenshots() throws {
        executionTimeAllowance = 120
        let out = try folder()
        let today = { CoachTodayView(model: CoachAthleteListModel.previewModel(Self.roster()),
                                     onShareInvite: {}, open: { _ in }, retry: {}) }
        try render(VStack { today() }, name: "05-coach-roster-default", height: 1100, to: out)
        try render(VStack { today() }, name: "06-coach-roster-xxl", size: .xxxLarge, height: 1700, to: out)
        try render(VStack { today() }, name: "07-coach-roster-rtl", rtl: true, height: 1100, to: out)
        let cards = VStack(alignment: .leading, spacing: 14) {
            RunnerNamePromptCard(onAdd: {}, onDismiss: {})
            CoachDisplayNameCard(onAdd: {})
        }
        try render(cards, name: "08-name-cards", height: 420, to: out)
        try render(cards, name: "09-name-cards-xxl", size: .xxxLarge, height: 640, to: out)
    }
}
