import SwiftUI
import UIKit
import XCTest
@testable import IOS_RunSmart_app

/// Renders Coach Today with fixture data on a simulator and writes PNGs. It does nothing unless
/// `TEST_RUNNER_COACH_TODAY_SHOTS=<folder>` is set, so normal test runs skip it:
///
///     TEST_RUNNER_COACH_TODAY_SHOTS=/tmp/coach-today xcodebuild test ... -only-testing:"IOS RunSmart appTests/CoachTodayScreenshotTests"
@MainActor
final class CoachTodayScreenshotTests: XCTestCase {
    private func folder() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["COACH_TODAY_SHOTS"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_COACH_TODAY_SHOTS to write screenshots.")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func render(
        _ snapshot: CoachTodaySnapshot, name: String, size: DynamicTypeSize = .large, rtl: Bool = false,
        height: CGFloat = 1400, offsetY: CGFloat = 0, viewport: CGFloat? = nil, to folder: URL
    ) throws {
        let model = CoachAthleteListModel.previewModel(snapshot)
        let content = VStack(alignment: .leading, spacing: 14) {
            CoachTodayView(model: model, onShareInvite: {}, open: { _ in }, retry: {})
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 390, height: height, alignment: .topLeading)
        .background(Color.surfaceBase)
        .offset(y: -offsetY)
        .frame(width: 390, height: viewport ?? height, alignment: .topLeading)
        .clipped()
        .environment(\.locale, Locale(identifier: "en_GB"))
        .environment(\.dynamicTypeSize, size)
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
        .preferredColorScheme(.dark)

        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = UIColor(Color.surfaceBase)
        let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: 390, height: viewport ?? height)))
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

    func testWriteScreenshots() throws {
        executionTimeAllowance = 120
        let out = try folder()
        for (index, offset) in [0, 844, 1688].enumerated() {
            try render(.previewFixture(athletes: 30), name: "01-thirty-athletes-\(index + 1)", height: 5200,
                       offsetY: CGFloat(offset), viewport: 844, to: out)
        }
        try render(.previewFixture(athletes: 6, runsLoaded: false), name: "02-partial-data-runs-failed", to: out)
        try render(Self.caughtUp(), name: "03-caught-up", to: out)
        try render(.previewFixture(athletes: 4), name: "04-xxl", size: .xxxLarge, height: 1800, to: out)
        try render(.previewFixture(athletes: 3), name: "05-ax3-text-dots", size: .accessibility3, height: 2200, to: out)
        try render(.previewFixture(athletes: 4), name: "06-rtl", rtl: true, height: 1200, to: out)
        try render(Self.empty(), name: "07-no-athletes", height: 500, to: out)
        // C7.2: "New to review" and the "{n} new" markers (dot plus text), including urgent rows with news.
        try render(.previewFixture(athletes: 10, withNews: true), name: "08-new-to-review", height: 2400,
                   viewport: 1400, to: out)
        try render(.previewFixture(athletes: 10, withNews: true), name: "09-new-to-review-xxl", size: .xxxLarge,
                   height: 4000, viewport: 1800, to: out)
        try render(.previewFixture(athletes: 10, withNews: true), name: "10-new-to-review-rtl", rtl: true,
                   height: 2400, viewport: 1400, to: out)
        // C7.4: the pain group first, "Pain · 2", note previews (one Hebrew), a deleted run, and the flags-failed banner.
        try render(.previewFixture(athletes: 10, withNews: true, withFlags: true), name: "11-pain-group", height: 2800,
                   viewport: 1400, to: out)
        try render(.previewFixture(athletes: 10, withNews: true, withFlags: true), name: "12-pain-group-rtl", rtl: true,
                   height: 2800, viewport: 1400, to: out)
        try render(.previewFixture(athletes: 10, withNews: true, withFlags: true), name: "13-pain-group-xxl",
                   size: .xxxLarge, height: 4400, viewport: 1800, to: out)
        try render(.previewFixture(athletes: 6, withFlags: true, flagsLoaded: false), name: "14-pain-flags-failed",
                   height: 1400, to: out)
    }

    // MARK: Fixtures

    private static var now: Date { Date(timeIntervalSince1970: 1_795_000_000) }

    private static var week: CoachAthleteWeek {
        CoachAthleteWeek(now: now, locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "Asia/Jerusalem")!)
    }

    static func empty() -> CoachTodaySnapshot {
        CoachTodaySnapshot.make(athletes: [], workouts: [], runs: [], now: now, week: week, locale: Locale(identifier: "en_GB"))
    }

    /// Everyone ran yesterday and has today's workout still to do: nobody needs the coach.
    static func caughtUp() -> CoachTodaySnapshot {
        let calendar = week.calendar
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let names = ["Yoni", "Noa", "Avi", "Maya", "Dana"]
        var athletes: [CoachAthleteSummary] = []
        var workouts: [CoachWorkoutSummary] = []
        var runs: [CoachRunSummary] = []
        for (index, name) in names.enumerated() {
            let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!
            athletes.append(CoachAthleteSummary(athleteID: id, displayName: name, linkedAt: now.addingTimeInterval(-86_400 * 30), hasActivePlan: true))
            let past = UUID()
            workouts.append(try! decodeWorkout(past, id, CoachReadDay.iso(yesterday, calendar: calendar), "easy"))
            runs.append(try! decodeRun(index + 1, id, past, yesterday.addingTimeInterval(8 * 3600)))
            // Dana rests today; the others have a tempo run still to do (it is before 20:00).
            if index < 4 { workouts.append(try! decodeWorkout(UUID(), id, CoachReadDay.iso(today, calendar: calendar), "tempo")) }
        }
        return CoachTodaySnapshot.make(
            athletes: athletes, workouts: workouts, runs: runs, now: now, week: week, locale: Locale(identifier: "en_GB")
        )
    }

    private static func decodeWorkout(_ id: UUID, _ athlete: UUID, _ date: String, _ type: String) throws -> CoachWorkoutSummary {
        try JSONDecoder().decode(CoachWorkoutSummary.self, from: Data("""
        {"id":"\(id)","athlete_id":"\(athlete)","plan_id":"\(UUID())","scheduled_date":"\(date)","type":"\(type)",
        "planned_distance":5,"planned_duration_minutes":30,"completed":false}
        """.utf8))
    }

    private static func decodeRun(_ id: Int, _ athlete: UUID, _ workout: UUID, _ at: Date) throws -> CoachRunSummary {
        try JSONDecoder().decode(CoachRunSummary.self, from: Data("""
        {"id":\(id),"athlete_id":"\(athlete)","workout_id":"\(workout)",
        "completed_at":"\(ISO8601DateFormatter().string(from: at))","distance_km":5,"duration_seconds":1650}
        """.utf8))
    }
}
