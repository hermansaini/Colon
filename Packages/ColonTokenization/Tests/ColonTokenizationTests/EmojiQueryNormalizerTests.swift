import XCTest
@testable import ColonTokenization

final class EmojiQueryNormalizerTests: XCTestCase {
    func testNormalizesApprovedASCIICharacters() {
        XCTAssertEqual(EmojiQueryNormalizer.normalize("Raised_Fist-2+C++"), "raised_fist-2+c++")
    }

    func testRejectsWhitespacePunctuationAndNonASCIICharacters() {
        XCTAssertNil(EmojiQueryNormalizer.normalize("raised fist"))
        XCTAssertNil(EmojiQueryNormalizer.normalize("fist!"))
        XCTAssertNil(EmojiQueryNormalizer.normalize("café"))
    }
}
