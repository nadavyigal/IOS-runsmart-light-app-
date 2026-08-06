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

    func testMapsExpiredCallbackToRecoveryCopy() throws {
        let expiredLink = try XCTUnwrap(
            URL(
                string: "https://www.runsmart-ai.com/auth/callback?source=ios&error=access_denied&error_code=otp_expired"
            )
        )

        XCTAssertEqual(
            RunSmartAuthCallback.errorMessage(from: expiredLink),
            "This confirmation link has expired. Return to sign in and request a new one."
        )
    }

    func testMapsUnknownCallbackFailureToSafeGenericCopy() throws {
        let failedLink = try XCTUnwrap(
            URL(
                string: "runsmart://auth/callback?error=server_error&error_description=raw-internal-detail"
            )
        )

        let message = RunSmartAuthCallback.errorMessage(from: failedLink)
        XCTAssertEqual(
            message,
            "RunSmart could not complete that sign-in link. Please return to sign in and try again."
        )
        XCTAssertFalse(message?.contains("raw-internal-detail") == true)
    }
}
