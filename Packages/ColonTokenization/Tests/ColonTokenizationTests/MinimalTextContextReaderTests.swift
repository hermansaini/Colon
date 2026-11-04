import Foundation
import XCTest
@testable import ColonTokenization

final class MinimalTextContextReaderTests: XCTestCase {
    func testReadsOnlyMaximumContextBeforeCaret() throws {
        let client = FakeTextClient(text: String(repeating: "a", count: 300) + " :f")
        let result = try XCTUnwrap(MinimalTextContextReader().read(from: client))

        XCTAssertEqual((result.snapshot.textBeforeCaret as NSString).length, 256)
        XCTAssertEqual(result.snapshot.textBeforeCaret.suffix(3), " :f")
        XCTAssertEqual(result.documentContextRange, NSRange(location: 47, length: 256))
        XCTAssertEqual(client.lastProposedRange, result.documentContextRange)
    }

    func testMapsUTF16LocalTokenRangeBackToDocument() throws {
        let client = FakeTextClient(text: "😀 hello :f")
        let context = try XCTUnwrap(MinimalTextContextReader().read(from: client))
        let detection = EmojiTokenDetector().detect(in: context.snapshot)
        let localRange = try XCTUnwrap(detection.replacementRange)

        XCTAssertEqual(localRange, NSRange(location: 9, length: 2))
        XCTAssertEqual(context.documentRange(for: localRange), NSRange(location: 9, length: 2))
    }

    func testUsesActualRangeReturnedByClient() throws {
        let client = FakeTextClient(
            text: "prefix :f",
            actualRangeOverride: NSRange(location: 3, length: 6),
            returnedTextOverride: "fix :f"
        )
        let context = try XCTUnwrap(MinimalTextContextReader().read(from: client))

        XCTAssertEqual(context.documentContextRange, NSRange(location: 3, length: 6))
        XCTAssertEqual(
            context.documentRange(for: NSRange(location: 4, length: 2)),
            NSRange(location: 7, length: 2)
        )
    }

    func testRejectsMissingSelectionAndMismatchedRanges() {
        let missing = FakeTextClient(text: "abc", selectedRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertNil(MinimalTextContextReader().read(from: missing))

        let mismatch = FakeTextClient(
            text: "abc",
            actualRangeOverride: NSRange(location: 0, length: 2),
            returnedTextOverride: "abc"
        )
        XCTAssertNil(MinimalTextContextReader().read(from: mismatch))
    }

    func testRejectsSelectionsAndInvalidClientRanges() {
        let selection = FakeTextClient(
            text: "abc",
            selectedRange: NSRange(location: 1, length: 2)
        )
        XCTAssertNil(MinimalTextContextReader().read(from: selection))

        let negativeCaret = FakeTextClient(
            text: "abc",
            selectedRange: NSRange(location: -1, length: 0)
        )
        XCTAssertNil(MinimalTextContextReader().read(from: negativeCaret))

        let negativeActualRange = FakeTextClient(
            text: "abc",
            selectedRange: NSRange(location: 3, length: 0),
            actualRangeOverride: NSRange(location: -1, length: 4),
            returnedTextOverride: "abcd"
        )
        XCTAssertNil(MinimalTextContextReader().read(from: negativeActualRange))
    }

    func testRejectsHostRangesThatExceedTheRequestedBound() {
        let text = String(repeating: "a", count: 300)
        let client = FakeTextClient(
            text: text,
            selectedRange: NSRange(location: 300, length: 0),
            actualRangeOverride: NSRange(location: 0, length: 300),
            returnedTextOverride: text
        )

        XCTAssertNil(MinimalTextContextReader().read(from: client))
    }

    func testRejectsDocumentRangeMappingToNotFound() {
        let context = MinimalTextContext(
            snapshot: TextContextSnapshot(textBeforeCaret: "a"),
            documentContextRange: NSRange(location: Int.max - 1, length: 1)
        )

        XCTAssertNil(context.documentRange(for: NSRange(location: 1, length: 0)))
    }

    func testKnownTokenStartRequiresACompleteContextPrefix() {
        let atDocumentStart = MinimalTextContext(
            snapshot: TextContextSnapshot(textBeforeCaret: ":f"),
            documentContextRange: NSRange(location: 0, length: 2)
        )
        let truncatedAtColon = MinimalTextContext(
            snapshot: TextContextSnapshot(textBeforeCaret: ":f"),
            documentContextRange: NSRange(location: 100, length: 2)
        )

        XCTAssertTrue(atDocumentStart.hasKnownTokenStart(at: 0))
        XCTAssertFalse(truncatedAtColon.hasKnownTokenStart(at: 0))
        XCTAssertTrue(truncatedAtColon.hasKnownTokenStart(at: 1))
        XCTAssertFalse(truncatedAtColon.hasKnownTokenStart(at: -1))
    }
}

private final class FakeTextClient: MinimalTextClient {
    let text: NSString
    let selectedRange: NSRange
    let actualRangeOverride: NSRange?
    let returnedTextOverride: String?
    private(set) var lastProposedRange: NSRange?

    init(
        text: String,
        selectedRange: NSRange? = nil,
        actualRangeOverride: NSRange? = nil,
        returnedTextOverride: String? = nil
    ) {
        self.text = text as NSString
        self.selectedRange = selectedRange ?? NSRange(location: self.text.length, length: 0)
        self.actualRangeOverride = actualRangeOverride
        self.returnedTextOverride = returnedTextOverride
    }

    func substring(in proposedRange: NSRange) -> TextClientSubstring? {
        lastProposedRange = proposedRange
        let actualRange = actualRangeOverride ?? proposedRange
        let returnedText = returnedTextOverride ?? text.substring(with: actualRange)
        return TextClientSubstring(text: returnedText, actualRange: actualRange)
    }
}
