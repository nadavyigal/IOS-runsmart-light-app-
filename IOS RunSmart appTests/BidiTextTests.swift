import SwiftUI
import XCTest
@testable import IOS_RunSmart_app

/// C7.15 (folded into C7.3): mixed-direction fixtures from v1.3. Pure Hebrew, pure
/// English, "6×800 ב-4:00", English with a Hebrew name, and emoji.
final class BidiTextTests: XCTestCase {
    func testParagraphDirectionComesFromTheFirstStrongCharacter() {
        XCTAssertEqual(BidiText.paragraphDirection("ריצה טובה היום"), .rightToLeft)
        XCTAssertEqual(BidiText.paragraphDirection("Great run today"), .leftToRight)
        XCTAssertEqual(BidiText.paragraphDirection("6×800 ב-4:00"), .rightToLeft, "digits are weak; ב decides")
        XCTAssertEqual(BidiText.paragraphDirection("Ran with דנה today"), .leftToRight)
        XCTAssertEqual(BidiText.paragraphDirection("🏃‍♀️💪 קשה"), .rightToLeft)
        XCTAssertNil(BidiText.paragraphDirection("🏃‍♀️💪"))
        XCTAssertNil(BidiText.paragraphDirection("4:00 / 6×800"))
        XCTAssertNil(BidiText.paragraphDirection(""))
    }

    func testIsolateWrapsANameInFSIAndPDI() {
        XCTAssertEqual(BidiText.isolate("דנה"), "\u{2068}דנה\u{2069}")
    }

    func testFillIsolatesHebrewNamesAndKeepsPunctuationInPlace() {
        XCTAssertEqual(BidiText.fill("Shared with {Coach}", ["Coach": "דנה"]), "Shared with \u{2068}דנה\u{2069}")
        XCTAssertEqual(BidiText.fill("{Coach} can see your note.", ["Coach": "דנה"]),
                       "\u{2068}דנה\u{2069} can see your note.")
        XCTAssertEqual(BidiText.fill("Hide note from {Coach}", ["Coach": "Dana"]), "Hide note from \u{2068}Dana\u{2069}")
        XCTAssertEqual(BidiText.fill("No placeholder", ["Coach": "Dana"]), "No placeholder")
    }

    func testServerLengthCountsCodePointsLikePostgresCharLength() {
        let emoji = String(repeating: "🏃", count: 1_000)
        XCTAssertEqual(BidiText.serverLength(emoji), 1_000)
        XCTAssertEqual(emoji.utf16.count, 2_000, "UTF-16 is not the server unit")
        XCTAssertTrue(BidiText.fits(emoji, limit: 1_000), "the SQL test stores 1000 emoji in a 1000 limit")
        XCTAssertFalse(BidiText.fits(emoji + "a", limit: 1_000))
        XCTAssertEqual(BidiText.serverLength("שלום"), 4)
    }

    func testTruncateNeverSplitsAGraphemeAndCountsTheEllipsis() {
        let family = "👨‍👩‍👧‍👦" // 7 code points, one grapheme
        let text = String(repeating: "א", count: 78) + family + " end"
        let cut = BidiText.truncate(text, limit: 80)
        XCTAssertEqual(cut, String(repeating: "א", count: 78) + "…")
        XCTAssertLessThanOrEqual(BidiText.serverLength(cut), 80)

        XCTAssertEqual(BidiText.truncate("ab🏃cdefgh", limit: 5), "ab🏃c…")
        XCTAssertEqual(BidiText.truncate("short", limit: 80), "short")
        XCTAssertEqual(BidiText.truncate("anything", limit: 0), "")
    }
}
