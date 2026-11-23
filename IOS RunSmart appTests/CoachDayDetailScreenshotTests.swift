import SwiftUI
import UIKit
import XCTest
@testable import IOS_RunSmart_app

/// C7.3 AC4: renders the coach's day detail with fixture data on a simulator and writes PNGs. It does
/// nothing unless `TEST_RUNNER_COACH_DAY_SHOTS=<folder>` is set, so normal test runs skip it:
///
///     TEST_RUNNER_COACH_DAY_SHOTS=/tmp/coach-day xcodebuild test ... -only-testing:"IOS RunSmart appTests/CoachDayDetailScreenshotTests"
@MainActor
final class CoachDayDetailScreenshotTests: XCTestCase {
    private let athlete = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private let now = ISO8601DateFormatter().date(from: "2026-11-18T12:00:00Z")!

    private func folder() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["COACH_DAY_SHOTS"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_COACH_DAY_SHOTS to write screenshots.")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func render(
        _ day: CoachDay, sharing: CoachDaySharing?, name: String, size: DynamicTypeSize = .large,
        rtl: Bool = false, height: CGFloat = 900, to folder: URL
    ) throws {
        let calendar = CoachAthleteWeek(now: now, locale: Locale(identifier: "en_GB"), timeZone: .gmt).calendar
        let content = CoachDayDetailContent(day: day, calendar: calendar, sharing: sharing)
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

    func testWriteScreenshots() throws {
        executionTimeAllowance = 120
        let out = try folder()
        let english = CoachDaySharing(athleteName: "Yoni", notes: [
            1: "Legs felt heavy after yesterday's hills. Slowed down for the last 2 km.",
            2: "Extra loop with Noa, very relaxed."
        ])
        let hebrew = CoachDaySharing(athleteName: "יוני", notes: [
            1: "הרגליים היו כבדות אחרי העליות של אתמול. האטתי ב-2 הק\"מ האחרונים.",
            2: "סיבוב נוסף עם נועה, רגוע מאוד."
        ])
        let day = try fixtureDay(firstRPE: 7, secondRPE: 4)
        try render(day, sharing: english, name: "01-effort-and-note", height: 1100, to: out)
        try render(day, sharing: hebrew, name: "02-hebrew-note-in-english-ui", height: 1100, to: out)
        try render(day, sharing: english, name: "03-rtl-layout", rtl: true, height: 1100, to: out)
        try render(day, sharing: english, name: "04-xxxl", size: .xxxLarge, height: 1700, to: out)
        try render(try fixtureDay(firstRPE: 7, secondRPE: nil, notes: false), sharing: english,
                   name: "05-effort-only-no-note", height: 1000, to: out)
        try render(day, sharing: nil, name: "06-flag-off-shows-nothing", height: 1000, to: out)
    }

    // MARK: Fixtures

    /// Monday 16 Nov: a planned easy 8 km run with a linked run, plus an extra run the same day.
    private func fixtureDay(firstRPE: Int?, secondRPE: Int?, notes: Bool = true) throws -> CoachDay {
        let week = CoachAthleteWeek(now: now, locale: Locale(identifier: "en_GB"), timeZone: .gmt)
        let workoutID = UUID()
        let workout = try JSONDecoder().decode(CoachWorkoutSummary.self, from: Data("""
        {"id":"\(workoutID)","athlete_id":"\(athlete)","plan_id":"\(UUID())","scheduled_date":"2026-11-16",
        "type":"easy","planned_distance":8,"planned_duration_minutes":48,"target_pace":360,"completed":true}
        """.utf8))
        let runs = try [
            decodeRun(1, workout: workoutID, at: "2026-11-16T06:30:00Z", km: 7.6, seconds: 2810, rpe: firstRPE, note: notes),
            decodeRun(2, workout: nil, at: "2026-11-16T17:10:00Z", km: 3.2, seconds: 1260, rpe: secondRPE, note: notes)
        ]
        let result = CoachAthleteDays.weeks(workouts: [workout], runs: runs, now: now, week: week)
        return try XCTUnwrap(result.current.days.first { $0.iso == "2026-11-16" })
    }

    private func decodeRun(
        _ id: Int, workout: UUID?, at: String, km: Double, seconds: Int, rpe: Int?, note: Bool
    ) throws -> CoachRunSummary {
        try JSONDecoder().decode(CoachRunSummary.self, from: Data("""
        {"id":\(id),"athlete_id":"\(athlete)","workout_id":\(workout.map { "\"\($0)\"" } ?? "null"),
        "completed_at":"\(at)","distance_km":\(km),"duration_seconds":\(seconds),"average_heart_rate":148,
        "rpe":\(rpe.map(String.init) ?? "null"),"has_note":\(note)}
        """.utf8))
    }
}
