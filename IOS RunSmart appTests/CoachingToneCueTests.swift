import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class CoachingToneCueTests: XCTestCase {
    private var savedCueSettings: RunCueSettings!

    override func setUp() async throws {
        savedCueSettings = LocalRunCueService.shared.settings
        LocalRunCueService.shared.settings = RunCueSettings()
        LocalRunCueService.shared.speechHandler = nil
    }

    override func tearDown() async throws {
        LocalRunCueService.shared.speechHandler = nil
        LocalRunCueService.shared.settings = savedCueSettings
    }

    func testOneToneListIsMotivatingCalmAndTechnical() {
        XCTAssertEqual(CoachingTone.options.map(\.label), ["Motivating", "Calm", "Technical"])
        XCTAssertEqual(OnboardingView.toneOptions, CoachingTone.options.map(\.label))
        XCTAssertEqual(Set(CoachingTone.options.map(\.storedStyle)).count, 3)
        XCTAssertFalse(CoachingTone.options.map(\.label).contains("Direct"))
        XCTAssertFalse(CoachingTone.options.map(\.label).contains("Strict"))
        XCTAssertFalse(CoachingTone.options.map(\.label).contains("Supportive"))
    }

    func testEachToneRoundTripsToItsStoredStyleAndBackToTheLabel() {
        XCTAssertEqual(CoachingTone.motivating.storedStyle, "encouraging")
        XCTAssertEqual(CoachingTone.calm.storedStyle, "supportive")
        XCTAssertEqual(CoachingTone.technical.storedStyle, "analytical")
        for tone in CoachingTone.options {
            XCTAssertEqual(CoachingTone.storedStyle(for: tone.label), tone.storedStyle)
            XCTAssertEqual(CoachingTone.displayLabel(for: tone.storedStyle), tone.label)
            XCTAssertEqual(CoachingTone.voiceTone(for: tone.storedStyle), tone)
            XCTAssertEqual(CoachingTone.voiceTone(for: tone.label), tone)
        }
    }

    func testLegacyStrictStaysReadableAndSpeaksAsMotivating() {
        XCTAssertEqual(CoachingTone.displayLabel(for: "challenging"), "Strict")
        XCTAssertEqual(CoachingTone.displayLabel(for: "Strict"), "Strict")
        XCTAssertEqual(CoachingTone.storedStyle(for: "Strict"), "challenging")
        XCTAssertEqual(CoachingTone.storedStyle(for: "challenging"), "challenging")
        XCTAssertEqual(CoachingTone.voiceTone(for: "challenging"), .motivating)
        XCTAssertEqual(CoachingTone.voiceTone(for: "Strict"), .motivating)
    }

    func testDirectStaysReadableAndCalmIsTheSupportiveLabel() {
        XCTAssertEqual(CoachingTone.displayLabel(for: "Direct"), "Direct")
        XCTAssertEqual(CoachingTone.storedStyle(for: "Direct"), "supportive")
        XCTAssertEqual(CoachingTone.voiceTone(for: "Direct"), .calm)
        XCTAssertEqual(CoachingTone.displayLabel(for: "supportive"), "Calm")
        XCTAssertEqual(CoachingTone.displayLabel(for: "encouraging"), "Motivating")
        XCTAssertEqual(CoachingTone.displayLabel(for: "analytical"), "Technical")
    }

    func testChoosingCalmSavesTheCalmLabelAndSupportiveStyle() {
        let saved = CoachingToneSave.make(from: "Calm", profile: .empty)
        XCTAssertEqual(saved.profile.coachingTone, "Calm")
        XCTAssertEqual(saved.profile.supabaseCoachingStyle, "supportive")
        XCTAssertEqual(saved.voiceTone, .calm)

        var request = TrainingGoalRequest.onboardingDefault(from: saved.profile)
        request.coachingTone = saved.profile.coachingTone
        XCTAssertEqual(request.supabaseCoachingStyle, "supportive")
    }

    func testChoosingTechnicalAndMotivatingSaveDifferentStyles() {
        let technical = CoachingToneSave.make(from: "Technical", profile: .empty)
        let motivating = CoachingToneSave.make(from: "Motivating", profile: .empty)
        XCTAssertEqual(technical.profile.coachingTone, "Technical")
        XCTAssertEqual(technical.profile.supabaseCoachingStyle, "analytical")
        XCTAssertEqual(motivating.profile.supabaseCoachingStyle, "encouraging")
        XCTAssertNotEqual(technical.profile.supabaseCoachingStyle, motivating.profile.supabaseCoachingStyle)
    }

    func testSavedToneRoundTripsInItsOwnDefaultsSuite() throws {
        let suite = "coaching-tone-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(CoachingToneStore.load(defaults: defaults), .motivating)
        CoachingToneStore.save(.technical, defaults: defaults)
        XCTAssertEqual(CoachingToneStore.load(defaults: defaults), .technical)
        CoachingToneStore.save(.calm, defaults: defaults)
        XCTAssertEqual(CoachingToneStore.load(defaults: defaults), .calm)
    }

    func testSplitFactsStayAndEachToneAddsItsOwnLeadIn() {
        let facts = "1 kilometer. Split pace 5 minutes 0 seconds per kilometer. Moving time 5 minutes 0 seconds."
        XCTAssertEqual(CoachCueSpeech.splitLine(facts: facts, tone: .motivating), "Push on. \(facts)")
        XCTAssertEqual(CoachCueSpeech.splitLine(facts: facts, tone: .calm), "Settle in. \(facts)")
        XCTAssertEqual(CoachCueSpeech.splitLine(facts: facts, tone: .technical), "Split check. \(facts)")
        let lines = CoachingTone.options.map { CoachCueSpeech.splitLine(facts: facts, tone: $0) }
        XCTAssertEqual(Set(lines).count, 3)
    }

    func testLifecycleLinesStayDistinctAndMotivatingKeepsTheCurrentSentences() {
        XCTAssertEqual(CoachCueSpeech.line(for: .started, tone: .motivating), "Run started.")
        XCTAssertEqual(CoachCueSpeech.line(for: .restored, tone: .motivating), "Run restored. Paused.")
        XCTAssertEqual(CoachCueSpeech.line(for: .paused, tone: .motivating), "Run paused.")
        XCTAssertEqual(CoachCueSpeech.line(for: .autoPaused, tone: .motivating), "Auto-paused.")
        XCTAssertEqual(CoachCueSpeech.line(for: .resumed, tone: .motivating), "Run resumed.")
        XCTAssertEqual(
            CoachCueSpeech.line(for: .finished(detail: "1.00 kilometers. Moving time 5 minutes 0 seconds"), tone: .motivating),
            "Run finished. 1.00 kilometers. Moving time 5 minutes 0 seconds"
        )

        let calmStart = CoachCueSpeech.line(for: .started, tone: .calm)
        let technicalStart = CoachCueSpeech.line(for: .started, tone: .technical)
        XCTAssertNotEqual(calmStart, "Run started.")
        XCTAssertNotEqual(technicalStart, "Run started.")
        XCTAssertNotEqual(calmStart, technicalStart)
        XCTAssertTrue(calmStart.hasPrefix("Run started."))
        XCTAssertTrue(technicalStart.hasPrefix("Run started."))

        for event in [CoachCueEvent.paused, .autoPaused, .resumed] {
            let spoken = Set(CoachingTone.options.map { CoachCueSpeech.line(for: event, tone: $0) })
            XCTAssertEqual(spoken.count, 3, "\(event) must sound different for each tone")
        }
    }

    func testTheThreeTonesUseDifferentSystemSpeech() {
        XCTAssertLessThan(CoachingTone.calm.speechRate, CoachingTone.motivating.speechRate)
        XCTAssertGreaterThan(CoachingTone.technical.speechRate, CoachingTone.motivating.speechRate)
        let pitches = Set(CoachingTone.options.map(\.pitchMultiplier))
        XCTAssertEqual(pitches.count, 3)

        let prepared = CoachCueSpeech.prepared(text: "Run paused.", tone: .calm)
        XCTAssertEqual(prepared.text, "Run paused.")
        XCTAssertEqual(prepared.rate, CoachingTone.calm.speechRate)
        XCTAssertEqual(prepared.pitchMultiplier, CoachingTone.calm.pitchMultiplier)
    }

    func testSpokenCuesSayTheyAreInEnglish() {
        XCTAssertTrue(CoachCueSpeech.spokenLanguageNote.contains("English"))
        XCTAssertTrue(CoachCueSpeech.spokenLanguageNote.contains("Distance"))
    }

    func testACalmChoiceChangesTheSpokenSplitAndThePreparedVoice() {
        var spoken: [String] = []
        let service = LocalRunCueService.shared
        service.speechHandler = { spoken.append($0) }
        service.begin(tone: .calm)
        XCTAssertEqual(spoken, [CoachCueSpeech.line(for: .started, tone: .calm)])
        XCTAssertEqual(service.lastPreparedSpeech, CoachCueSpeech.prepared(text: spoken[0], tone: .calm))

        spoken.removeAll()
        service.update(
            distance: 1_000,
            movingTime: 300,
            guide: [.init(text: "Rep 3 of 6.", isReminder: false)],
            tone: .technical
        )

        let line = spoken.first ?? ""
        XCTAssertTrue(line.hasPrefix("Split check. 1 kilometer."))
        XCTAssertTrue(line.contains("Split pace 5 minutes 0 seconds per kilometer."))
        XCTAssertTrue(line.contains("Moving time 5 minutes 0 seconds."))
        XCTAssertTrue(line.hasSuffix("Rep 3 of 6."))
        XCTAssertEqual(service.lastPreparedSpeech?.rate, CoachingTone.technical.speechRate)
        XCTAssertEqual(service.lastPreparedSpeech?.pitchMultiplier, CoachingTone.technical.pitchMultiplier)
    }

    func testVoiceCueRequestCarriesTheStoredStyle() throws {
        let context = VoiceCueContext(
            elapsedMinutes: 10,
            distanceKm: 2,
            currentPaceMinPerKm: 5.5,
            coachingStyle: CoachingTone.technical.storedStyle
        )
        let request = try XCTUnwrap(VoiceCoachService.voiceCueRequest(
            context: context,
            baseURLString: "https://runsmart-ai.com",
            accessToken: "jwt-token"
        ))
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["coachingStyle"] as? String, "analytical")
        XCTAssertEqual(json["elapsedMinutes"] as? Double, 10)
    }
}
