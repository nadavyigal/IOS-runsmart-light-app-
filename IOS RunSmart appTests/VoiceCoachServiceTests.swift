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
}
