import XCTest
@testable import IOS_RunSmart_app

/// The bare domain answered with a 308 redirect to www, and URLSession drops the
/// Authorization header on a cross-host redirect. Every signed-in API call then
/// reached the server without its token and failed with 401 (plan generation since
/// 2026-09-27). The app must call the host that serves the API directly.
final class APIBaseURLTests: XCTestCase {
    func testTheConfiguredAPIBaseIsTheWwwHost() {
        XCTAssertEqual(URLSessionRunSmartAPIClient.configuredBaseURL().host, "www.runsmart-ai.com")
    }

    func testTheInfoPlistValueIsTheWwwHost() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "RunSmartAPIBaseURL") as? String
        XCTAssertEqual(raw.flatMap { URL(string: $0)?.host }, "www.runsmart-ai.com")
    }
}
