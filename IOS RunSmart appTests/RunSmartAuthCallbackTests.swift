import XCTest
@testable import IOS_RunSmart_app

final class RunSmartAuthCallbackTests: XCTestCase {
    func testSupabaseConfirmationReturnsToCanonicalIOSCallback() {
        XCTAssertEqual(
            RunSmartAuthCallback.redirectURL.absoluteString,
            "https://www.runsmart-ai.com/auth/callback?source=ios"
        )
    }

    func testRecognizesUniversalLinkAndCustomSchemeFallback() throws {
        let universalLink = try XCTUnwrap(
            URL(string: "https://www.runsmart-ai.com/auth/callback?source=ios&code=pkce-code")
        )
        let customScheme = try XCTUnwrap(
            URL(string: "runsmart://auth/callback?code=pkce-code")
        )

        XCTAssertTrue(RunSmartAuthCallback.matches(universalLink))
        XCTAssertTrue(RunSmartAuthCallback.matches(customScheme))
    }

    func testRejectsUnrelatedOrSpoofedLinks() throws {
        let garmin = try XCTUnwrap(URL(string: "runsmart://garmin/callback?code=oauth-code"))
        let spoofedHost = try XCTUnwrap(
            URL(string: "https://attacker.example/auth/callback?source=ios&code=pkce-code")
        )
        let webOnly = try XCTUnwrap(
            URL(string: "https://www.runsmart-ai.com/auth/callback?code=web-code")
        )

        XCTAssertFalse(RunSmartAuthCallback.matches(garmin))
        XCTAssertFalse(RunSmartAuthCallback.matches(spoofedHost))
        XCTAssertFalse(RunSmartAuthCallback.matches(webOnly))
    }
}
