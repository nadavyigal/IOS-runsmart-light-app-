import XCTest
import AuthenticationServices
import Supabase
@testable import IOS_RunSmart_app

/// Covers the second way into the app.
///
/// Root cause these pin, reproduced on a clean simulator 2026-07-26: with no
/// Apple Account signed in, tapping Sign in with Apple makes iOS show its own
/// "Sign in to your Apple Account" alert, and dismissing it returns a bare
/// `ASAuthorizationError` code 1000 with no underlying error — byte-identical
/// to the signature in the failing production sessions. Apple's `.unknown`
/// code does not prove every session had the same cause, but no change to the
/// Apple request can help a device without a usable account. While Apple was
/// the only door, that user was permanently locked out of a hard-gated app.
@MainActor
final class EmailSignInTests: XCTestCase {

    // MARK: - The lockout itself

    /// The regression that matters. Before this change the wall offered exactly
    /// one action, so a bare code 1000 was terminal. Fails against the previous
    /// copy, which ended "then tap to try again" — the advice that loops a
    /// blocked user forever.
    func testAppleFailureCopyOffersANonAppleWayIn() {
        let bareUnknown = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.unknown.rawValue
        )
        let mapped = SignInView.humanReadableAppleSignInError(for: bareUnknown)

        XCTAssertNotNil(mapped)
        XCTAssertTrue(
            mapped!.localizedCaseInsensitiveContains("email"),
            "a user whose device has no Apple Account cannot retry their way in — the copy must name the alternative"
        )
        // Guarantees carried over from WP-43 S2 and 1.1.2 (27); do not regress.
        XCTAssertTrue(mapped!.localizedCaseInsensitiveContains("iCloud"))
        XCTAssertTrue(mapped!.localizedCaseInsensitiveContains("nothing was created"))
        XCTAssertFalse(mapped!.contains("com.apple"))
        XCTAssertFalse(mapped!.contains("1000"))
    }

    /// A cancel is still silent. If this ever returns copy, every user who backs
    /// out of the sheet on purpose gets an error they did not earn.
    func testCancelStillProducesNoError() {
        let canceled = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.canceled.rawValue
        )
        XCTAssertNil(SignInView.humanReadableAppleSignInError(for: canceled))
    }

    // MARK: - Validation

    func testEmailValidationAcceptsOrdinaryAddressesAndRejectsImpossibleOnes() {
        XCTAssertTrue(EmailSignInModel.isValidEmail("runner@example.com"))
        XCTAssertTrue(EmailSignInModel.isValidEmail("first.last+tag@sub.example.co.uk"))

        XCTAssertFalse(EmailSignInModel.isValidEmail(""))
        XCTAssertFalse(EmailSignInModel.isValidEmail("runner"))
        XCTAssertFalse(EmailSignInModel.isValidEmail("runner@"))
        XCTAssertFalse(EmailSignInModel.isValidEmail("@example.com"))
        XCTAssertFalse(EmailSignInModel.isValidEmail("runner@example"))
        XCTAssertFalse(EmailSignInModel.isValidEmail("two@at@example.com"))
        XCTAssertFalse(EmailSignInModel.isValidEmail("run ner@example.com"))
    }

    func testPasswordFloorMatchesTheCopyShownToUsers() {
        XCTAssertFalse(EmailSignInModel.isAcceptablePassword(String(repeating: "a", count: 7)))
        XCTAssertTrue(EmailSignInModel.isAcceptablePassword(String(repeating: "a", count: 8)))
        XCTAssertEqual(EmailSignInModel.minimumPasswordLength, 8)
    }

    /// A pasted address with a stray capital or trailing space reads to the user
    /// as "wrong password" on an account that exists. Normalize before sending.
    func testAddressIsTrimmedAndLowercasedBeforeItLeavesTheDevice() async {
        var received: String?
        let model = EmailSignInModel(gateway: .init(
            signIn: { email, _ in received = email },
            signUp: { _, _ in .signedIn }
        ))
        model.email = "  Runner@Example.COM  "
        model.password = "correct-horse"

        await model.submit()

        XCTAssertEqual(received, "runner@example.com")
    }

    func testSubmitIsBlockedUntilBothFieldsAreUsable() {
        let model = EmailSignInModel(gateway: .init(
            signIn: { _, _ in },
            signUp: { _, _ in .signedIn }
        ))
        XCTAssertFalse(model.canSubmit, "empty form must not submit")

        model.email = "runner@example.com"
        XCTAssertFalse(model.canSubmit, "missing password must not submit")

        model.password = "short"
        XCTAssertFalse(model.canSubmit, "sub-minimum password must not submit")

        model.password = "long-enough"
        XCTAssertTrue(model.canSubmit)
    }

    // MARK: - Flow

    /// Confirmation-required is a success, not a failure. Supabase returns a
    /// session when the project has email confirmation off and a user with no
    /// session when it is on; the app cannot read that setting, so it must
    /// handle both rather than assume one.
    func testCreateAccountSurfacesConfirmationInsteadOfLookingLikeAFailure() async {
        let model = EmailSignInModel(gateway: .init(
            signIn: { _, _ in },
            signUp: { _, _ in .confirmationRequired }
        ))
        model.mode = .createAccount
        model.email = "new@example.com"
        model.password = "long-enough"

        await model.submit()

        XCTAssertEqual(model.phase, .confirmationRequired)
        XCTAssertNil(model.errorMessage, "an account awaiting confirmation is not an error")
    }

    func testCreateAccountWithConfirmationOffLandsStraightIn() async {
        let model = EmailSignInModel(gateway: .init(
            signIn: { _, _ in },
            signUp: { _, _ in .signedIn }
        ))
        model.mode = .createAccount
        model.email = "new@example.com"
        model.password = "long-enough"

        await model.submit()

        XCTAssertEqual(model.phase, .editing)
        XCTAssertNil(model.errorMessage)
    }

    /// A failed attempt must return the form to a usable state. If `phase`
    /// stuck at `.submitting`, `canSubmit` stays false and the user is locked
    /// out a second time by the very screen meant to rescue them.
    func testAFailedAttemptLeavesTheFormUsableAgain() async {
        struct Boom: Error {}
        let model = EmailSignInModel(gateway: .init(
            signIn: { _, _ in throw Boom() },
            signUp: { _, _ in .signedIn }
        ))
        model.email = "runner@example.com"
        model.password = "long-enough"

        await model.submit()

        XCTAssertEqual(model.phase, .editing)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.canSubmit, "the user must be able to try again immediately")
    }

    func testSwitchingModeClearsAStaleErrorAndLeavesConfirmation() {
        let model = EmailSignInModel(gateway: .init(
            signIn: { _, _ in },
            signUp: { _, _ in .signedIn }
        ))
        model.switchMode(to: .createAccount)
        XCTAssertEqual(model.mode, .createAccount)

        model.switchMode(to: .signIn)
        XCTAssertEqual(model.mode, .signIn)
        XCTAssertNil(model.errorMessage)
    }

    // MARK: - Error copy

    /// Same guarantee the Apple path carries: raw server text never reaches a
    /// user. A Postgres or URLError description on the sign-in screen is both
    /// unreadable and a potential leak.
    func testErrorCopyNeverForwardsRawErrorText() {
        let raw = NSError(
            domain: "PostgrestError",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "duplicate key value violates unique constraint \"users_pkey\""]
        )
        let mapped = EmailSignInModel.humanReadableError(for: raw, mode: .signIn)

        XCTAssertFalse(mapped.contains("duplicate key"))
        XCTAssertFalse(mapped.contains("users_pkey"))
        XCTAssertFalse(mapped.isEmpty)
    }

    func testOfflineErrorTellsTheUserItIsTheConnection() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let mapped = EmailSignInModel.humanReadableError(for: offline, mode: .signIn)

        XCTAssertTrue(
            mapped.localizedCaseInsensitiveContains("connection"),
            "an offline user must not be told their password is wrong"
        )
    }

    /// The two wrong-mode cases are the most common self-inflicted lockouts, and
    /// each is one sentence away from success.
    /// Observed 2026-07-26 while verifying the email path: a `signUp` whose
    /// confirmation email the provider refuses returns 500 and the account is
    /// rolled back, so retrying the same address can never succeed and the copy
    /// must not say "try again" — that is the same dead end Sign in with Apple
    /// already created.
    ///
    /// The trigger in that session was a reserved `example.com` address, which
    /// Resend rejects by design; this project's real sending path (Resend on a
    /// verified `runsmart-ai.com`) was confirmed delivering the same day. The
    /// handling stays because the same shape appears whenever the provider
    /// rejects an address, the domain loses verification, or quota runs out.
    func testUndeliverableConfirmationEmailDoesNotTellTheUserToRetry() {
        for code in [ErrorCode.emailAddressNotAuthorized, .unexpectedFailure] {
            let error = AuthError.api(
                message: "Error sending confirmation email",
                errorCode: code,
                underlyingData: Data(),
                underlyingResponse: HTTPURLResponse()
            )
            let mapped = EmailSignInModel.humanReadableError(for: error, mode: .createAccount)

            XCTAssertFalse(
                mapped.localizedCaseInsensitiveContains("try again"),
                "\(code.rawValue): retrying cannot fix an undeliverable confirmation email"
            )
            XCTAssertTrue(
                mapped.localizedCaseInsensitiveContains("no account was created"),
                "\(code.rawValue): the user must know nothing was half-created"
            )
            XCTAssertTrue(
                mapped.localizedCaseInsensitiveContains("Apple"),
                "\(code.rawValue): point the user at the door that still works"
            )
        }
    }

    func testUnexpectedFailureIsOnlyCalledAConfirmationFailureWhenEvidenceMatches() {
        let unrelated = AuthError.api(
            message: "Database temporarily unavailable",
            errorCode: .unexpectedFailure,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse()
        )
        let signIn = EmailSignInModel.humanReadableError(for: unrelated, mode: .signIn)
        let create = EmailSignInModel.humanReadableError(for: unrelated, mode: .createAccount)

        XCTAssertFalse(signIn.localizedCaseInsensitiveContains("confirmation email"))
        XCTAssertFalse(create.localizedCaseInsensitiveContains("confirmation email"))
        XCTAssertTrue(create.localizedCaseInsensitiveContains("nothing was created"))
    }

    func testModeSpecificCopyDistinguishesTheTwoWays() {
        let signIn = EmailSignInModel.humanReadableError(for: NSError(domain: "x", code: 1), mode: .signIn)
        let create = EmailSignInModel.humanReadableError(for: NSError(domain: "x", code: 1), mode: .createAccount)
        XCTAssertNotEqual(signIn, create)
        XCTAssertTrue(create.localizedCaseInsensitiveContains("nothing was created"))
    }
}
