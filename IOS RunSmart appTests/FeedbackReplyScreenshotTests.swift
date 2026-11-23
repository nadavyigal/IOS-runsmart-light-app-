import Combine
import SwiftUI
import UIKit
import XCTest
@testable import IOS_RunSmart_app

/// C7.7: renders the athlete's reply UI (P6) and the coach's replies under a note with fixture data and
/// writes PNGs. It does nothing unless `TEST_RUNNER_FEEDBACK_REPLY_SHOTS=<folder>` is set:
///
///     TEST_RUNNER_FEEDBACK_REPLY_SHOTS=/tmp/replies xcodebuild test ... -only-testing:"IOS RunSmart appTests/FeedbackReplyScreenshotTests"
@MainActor
final class FeedbackReplyScreenshotTests: XCTestCase {
    private let userID = UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000B")!
    private let coachID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!
    private let linkID = UUID(uuidString: "11111111-0000-4000-8000-000000000001")!
    private let noteID = UUID(uuidString: "D1000000-0000-4000-8000-00000000000B")!
    private let now = Date()

    private nonisolated final class Repo: AthleteFeedbackReplyRepository, @unchecked Sendable {
        var failWith: Error?
        func send(id: UUID, feedbackID: UUID, text: String) async throws { if let failWith { throw failWith } }
        func mine() async throws -> [FeedbackReplyServerRow] { [] }
    }

    private nonisolated final class NoEvents: AnalyticsTracking, @unchecked Sendable {
        func track(_ event: String, properties: [String: Any]) {}
        func identify(userId: String, traits: [String: Any]) {}
        func register(properties: [String: Any]) {}
        func unregister(_ key: String) {}
        func reset() {}
    }

    private nonisolated final class CoachRows: CoachFeedbackReplyFetching, @unchecked Sendable {
        let rows: [CoachFeedbackReply]
        init(_ rows: [CoachFeedbackReply]) { self.rows = rows }
        func replies(athleteIDs: [UUID]) async throws -> [CoachFeedbackReply] { rows }
        func markRead(replyIDs: [UUID]) async throws -> Int { 0 }
    }

    private func folder() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["FEEDBACK_REPLY_SHOTS"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_FEEDBACK_REPLY_SHOTS to write screenshots.")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var link: CoachLink { CoachLink(id: linkID, coachID: coachID, coachName: "Dana", consentedAt: now.addingTimeInterval(-30 * 86_400)) }

    private func sharing(linked: Bool = true, v2: Bool = true) -> RunSharingContext {
        RunSharingContext(v2Enabled: v2, userID: userID, linkID: linked ? linkID : nil, coachName: linked ? "Dana" : nil,
                          sharingActive: linked, sharingSince: linked ? now.addingTimeInterval(-86_400) : nil)
    }

    private func note(_ text: String = "Good week. Keep Thursday easy and sleep early before Saturday.") -> AthleteFeedbackNote {
        AthleteFeedbackNote(id: noteID, coachID: coachID, coachName: "Dana", weekStart: "2026-11-16", text: text,
                            createdAt: now.addingTimeInterval(-3 * 3_600))
    }

    /// A service holding one sent reply and, optionally, one still waiting to send.
    private func service(waiting: Bool, hebrew: Bool = false, context: RunSharingContext? = nil) async -> AthleteFeedbackReplyService {
        let repo = Repo()
        let defaults = UserDefaults(suiteName: "FeedbackReplyShots.\(UUID().uuidString)")!
        var clock = now.addingTimeInterval(-2 * 3_600)
        let service = AthleteFeedbackReplyService(repository: repo, defaults: defaults, keyPrefix: "shots",
                                                  analytics: { NoEvents() }, now: { clock },
                                                  sharing: Empty().eraseToAnyPublisher())
        await service.apply(sharing())
        await service.send(hebrew ? "תודה! הרגליים היו כבדות ביום שלישי, אז האטתי." : "Thanks! Legs felt heavy on Tuesday, so I slowed down.",
                           note: note(), link: link)
        if waiting {
            clock = now.addingTimeInterval(-600)
            repo.failWith = URLError(.notConnectedToInternet)
            await service.send("Should I still do the long run on Saturday?", note: note(), link: link)
        }
        if let context { await service.apply(context) }
        return service
    }

    private func render<V: View>(_ view: V, name: String, size: DynamicTypeSize = .large, rtl: Bool = false,
                                 height: CGFloat = 700, to folder: URL) throws {
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

    func testWriteScreenshots() async throws {
        executionTimeAllowance = 180
        let out = try folder()

        // Athlete (P6).
        let withReplies = await service(waiting: true)
        try render(AthleteFeedbackCard(note: note(), replyLink: link, replyService: withReplies),
                   name: "01-athlete-sent-and-waiting", to: out)
        try render(VStack { AthleteFeedbackCard(note: note(), replyLink: link, replyService: withReplies) },
                   name: "02-athlete-xxxl", size: .xxxLarge, height: 1300, to: out)
        let hebrew = await service(waiting: false, hebrew: true)
        try render(AthleteFeedbackCard(note: note(), replyLink: link, replyService: hebrew),
                   name: "03-athlete-hebrew-reply", to: out)
        try render(AthleteFeedbackCard(note: note(), replyLink: link, replyService: withReplies),
                   name: "04-athlete-rtl-layout", rtl: true, to: out)

        let empty = await service(waiting: false)
        try render(VStack(alignment: .leading, spacing: 10) {
            CoachFeedbackBody(text: note().text)
            FeedbackReplyThread(note: note(), link: link, service: empty,
                                draft: String(repeating: "Long reply from WhatsApp. ", count: 37))
        }, name: "05-composer-counter", height: 1400, to: out)
        try render(VStack(alignment: .leading, spacing: 10) {
            CoachFeedbackBody(text: note().text)
            FeedbackReplyThread(note: note(), link: link, service: empty,
                                draft: String(repeating: "Long reply from WhatsApp. ", count: 39))
        }, name: "06-composer-over-1000", height: 1450, to: out)

        // Link ended: replies stay, Reply hides (AC6).
        let left = await service(waiting: false, context: sharing(linked: false))
        try render(AthleteFeedbackCard(note: note(), replyLink: nil, replyService: left),
                   name: "07-athlete-link-ended", to: out)
        left.linkGoneNotice = (noteID, "Dana")
        try render(AthleteFeedbackCard(note: note(), replyLink: nil, replyService: left),
                   name: "08-athlete-link-gone-notice", to: out)

        // Coach v2 off: the card is the 1.2.6 read-only card.
        let off = await service(waiting: false, context: sharing(v2: false))
        try render(AthleteFeedbackCard(note: note(), replyLink: link, replyService: off),
                   name: "09-flag-off-read-only", to: out)

        // Coach (AC4): replies under the note in the week note / day detail.
        let store = CoachFeedbackStore(athleteID: userID, athleteName: "Yoni", service: MockCoachFeedbackService(),
                                       currentCoachID: { nil })
        store.upsert(CoachFeedback(id: noteID, athleteID: userID, target: .week("2026-11-16"),
                                   text: note().text, createdAt: now.addingTimeInterval(-3 * 3_600)))
        store.enableReplies(CoachRows([
            CoachFeedbackReply(id: UUID(), feedbackID: noteID, athleteID: userID,
                               text: "Thanks! Legs felt heavy on Tuesday, so I slowed down.",
                               createdAt: now.addingTimeInterval(-2 * 3_600)),
            CoachFeedbackReply(id: UUID(), feedbackID: noteID, athleteID: userID,
                               text: "שאלה: לעשות את הריצה הארוכה בשבת?", createdAt: now.addingTimeInterval(-600))
        ]))
        await store.loadReplies()
        let section = CoachFeedbackSection(store: store, target: .week("2026-11-16"), weekStart: "2026-11-16",
                                           buttonTitle: "Write a week note", open: { _ in })
        try render(section, name: "10-coach-replies-under-note", to: out)
        try render(section, name: "11-coach-replies-xxxl", size: .xxxLarge, height: 1300, to: out)
        let hebrewName = CoachFeedbackStore(athleteID: userID, athleteName: "יוני", service: MockCoachFeedbackService(),
                                            currentCoachID: { nil })
        hebrewName.upsert(CoachFeedback(id: noteID, athleteID: userID, target: .week("2026-11-16"),
                                        text: note().text, createdAt: now.addingTimeInterval(-3 * 3_600)))
        hebrewName.enableReplies(CoachRows(store.replies))
        await hebrewName.loadReplies()
        try render(CoachFeedbackSection(store: hebrewName, target: .week("2026-11-16"), weekStart: "2026-11-16",
                                        buttonTitle: "Write a week note", open: { _ in }),
                   name: "12-coach-hebrew-athlete-name", to: out)
    }
}
