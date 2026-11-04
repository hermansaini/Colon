import Foundation
import XCTest
@testable import ColonTokenization

final class EmojiTokenDetectorTests: XCTestCase {
    private let detector = EmojiTokenDetector()

    func testDetectsActiveQueryAtStartOfField() {
        let detection = detect(":f")

        XCTAssertEqual(detection.state, .activeQuery)
        XCTAssertEqual(detection.replacementRange, NSRange(location: 0, length: 2))
        XCTAssertEqual(detection.rawQuery, "f")
        XCTAssertEqual(detection.normalizedQuery, "f")
    }

    func testDetectsActiveQueryAfterWhitespace() {
        let detection = detect("hello :F")

        XCTAssertEqual(detection.state, .activeQuery)
        XCTAssertEqual(detection.replacementRange, NSRange(location: 6, length: 2))
        XCTAssertEqual(detection.rawQuery, "F")
        XCTAssertEqual(detection.normalizedQuery, "f")
    }

    func testRejectsAdjacentTextTimesAndURLs() {
        XCTAssertEqual(detect("hello:f").state, .inactive)
        XCTAssertEqual(detect("10:30").state, .inactive)
        XCTAssertEqual(detect("https://example.com").state, .inactive)
        XCTAssertEqual(detect("visit https://example.com").state, .inactive)
    }

    func testDetectsUnderscoreAndPlusQueries() {
        XCTAssertEqual(detect(":raised_fist").normalizedQuery, "raised_fist")
        XCTAssertEqual(detect(":c++").normalizedQuery, "c++")
    }

    func testWhitespaceTerminatesAndPunctuationInvalidatesToken() {
        XCTAssertEqual(detect(":f ").state, .inactive)

        let punctuation = detect(":f,")
        XCTAssertEqual(punctuation.state, .terminatedOrInvalid)
        XCTAssertEqual(punctuation.replacementRange, NSRange(location: 0, length: 3))
        XCTAssertNil(punctuation.normalizedQuery)
    }

    func testCalculatesUTF16RangeAfterEmojiAndNonASCIIText() {
        let afterEmoji = detect("😀 :f")
        XCTAssertEqual(afterEmoji.state, .activeQuery)
        XCTAssertEqual(afterEmoji.replacementRange, NSRange(location: 3, length: 2))

        let afterNonASCII = detect("é :f")
        XCTAssertEqual(afterNonASCII.state, .activeQuery)
        XCTAssertEqual(afterNonASCII.replacementRange, NSRange(location: 2, length: 2))

        XCTAssertEqual(detect("😀:f").state, .inactive)
    }

    func testDetectsTokenOnLatestLine() {
        let detection = detect("first line\n:f")

        XCTAssertEqual(detection.state, .activeQuery)
        XCTAssertEqual(detection.replacementRange, NSRange(location: 11, length: 2))
    }

    func testDeletionBackToColonOnlyState() {
        XCTAssertEqual(detect(":fi").state, .activeQuery)

        let detection = detect(":")
        XCTAssertEqual(detection.state, .colonOnly)
        XCTAssertEqual(detection.replacementRange, NSRange(location: 0, length: 1))
        XCTAssertEqual(detection.normalizedQuery, "")
    }

    func testDetectsClosingColonIntent() {
        let detection = detect(":Fist:")

        XCTAssertEqual(detection.state, .closingColonIntent)
        XCTAssertTrue(detection.hasClosingColonIntent)
        XCTAssertEqual(detection.replacementRange, NSRange(location: 0, length: 6))
        XCTAssertEqual(detection.rawQuery, "Fist")
        XCTAssertEqual(detection.normalizedQuery, "fist")
    }

    func testRejectsEmptyOrMultipleClosingColons() {
        XCTAssertEqual(detect("::").state, .terminatedOrInvalid)
        XCTAssertEqual(detect(":f::").state, .terminatedOrInvalid)
    }

    private func detect(_ textBeforeCaret: String) -> EmojiTokenDetection {
        detector.detect(in: TextContextSnapshot(textBeforeCaret: textBeforeCaret))
    }
}
