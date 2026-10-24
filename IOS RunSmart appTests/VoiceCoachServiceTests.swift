import XCTest
@testable import IOS_RunSmart_app

@MainActor
final class VoiceCoachServiceTests: XCTestCase {

    private let context = VoiceCueContext(
        elapsedMinutes: 10,
        distanceKm: 2,
        currentPaceMinPerKm: 5.5
    )

    func testSignedInRequestCarriesBearerToken() throws {
        let request = try XCTUnwrap(VoiceCoachService.voiceCueRequest(
            context: context,
            baseURLString: "https://runsmart-ai.com",
            accessToken: "jwt-token"
        ))

        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-token")
        XCTAssertEqual(request.url?.absoluteString, "https://runsmart-ai.com/api/coach/voice-cue")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotNil(request.httpBody)
    }

    func testGuestWithoutSessionBuildsNoRequest() {
        XCTAssertNil(VoiceCoachService.voiceCueRequest(
            context: context,
            baseURLString: "https://runsmart-ai.com",
            accessToken: nil
        ))
    }

    func testEmptyTokenBuildsNoRequest() {
        XCTAssertNil(VoiceCoachService.voiceCueRequest(
            context: context,
            baseURLString: "https://runsmart-ai.com",
            accessToken: ""
        ))
    }

    // MARK: Session lifecycle (Release A review)

    func testCueOnlyPlaysInTheSessionThatRequestedIt() {
        XCTAssertTrue(VoiceCoachService.shouldPlayCue(startedIn: 3, current: 3, isRunSessionLive: true, isEnabled: true))
        XCTAssertFalse(VoiceCoachService.shouldPlayCue(startedIn: 3, current: 4, isRunSessionLive: true, isEnabled: true), "a pause or stop after the request makes the cue stale")
        XCTAssertFalse(VoiceCoachService.shouldPlayCue(startedIn: 3, current: 3, isRunSessionLive: false, isEnabled: true))
        XCTAssertFalse(VoiceCoachService.shouldPlayCue(startedIn: 3, current: 3, isRunSessionLive: true, isEnabled: false))
    }

    func testPauseAndStopInvalidateAnInFlightCue() {
        let service = VoiceCoachService.shared
        let wasEnabled = service.isEnabled
        defer {
            service.stopSession()
            service.setEnabled(wasEnabled)
        }

        service.setEnabled(true)
        service.startSession()
        let requested = service.sessionGeneration
        XCTAssertTrue(service.isRunSessionLive)

        service.pauseSession()
        XCTAssertNotEqual(service.sessionGeneration, requested)
        XCTAssertFalse(service.isRunSessionLive)

        service.resumeSession()
        let afterResume = service.sessionGeneration
        service.stopSession()
        XCTAssertNotEqual(service.sessionGeneration, afterResume)
    }

    func testLocalCueInvalidatesAnInFlightServerCueButKeepsTheTimer() {
        let service = VoiceCoachService.shared
        let wasEnabled = service.isEnabled
        defer {
            service.stopSession()
            service.setEnabled(wasEnabled)
        }

        service.setEnabled(true)
        service.startSession()
        let requested = service.sessionGeneration

        service.cancelPlaybackForLocalCue()

        XCTAssertNotEqual(service.sessionGeneration, requested, "a server cue that returns after a local cue is stale")
        XCTAssertTrue(service.isRunSessionLive)
        XCTAssertTrue(service.isCueTimerRunning, "the 5 minute server cue timer is unaffected")
    }

    func testResumeWithoutStartRunsTheCueTimer() {
        let service = VoiceCoachService.shared
        let wasEnabled = service.isEnabled
        defer {
            service.stopSession()
            service.setEnabled(wasEnabled)
        }

        service.stopSession()
        service.setEnabled(true)
        service.resumeSession()  // a recovered run resumes without startSession()

        XCTAssertTrue(service.isRunSessionLive)
        XCTAssertTrue(service.isCueTimerRunning)
    }

    func testEnablingCuesMidRunRestartsTheTimer() {
        let service = VoiceCoachService.shared
        let wasEnabled = service.isEnabled
        defer {
            service.stopSession()
            service.setEnabled(wasEnabled)
        }

        service.setEnabled(true)
        service.startSession()
        XCTAssertTrue(service.isCueTimerRunning)

        service.setEnabled(false)
        XCTAssertFalse(service.isCueTimerRunning)
        XCTAssertTrue(service.isRunSessionLive, "switching cues off does not end the run session")

        service.setEnabled(true)
        XCTAssertTrue(service.isCueTimerRunning)

        service.stopSession()
        service.setEnabled(false)
        service.setEnabled(true)
        XCTAssertFalse(service.isCueTimerRunning, "no timer outside a live run")
    }
}
