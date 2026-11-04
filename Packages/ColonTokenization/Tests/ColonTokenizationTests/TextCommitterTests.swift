import Foundation
import XCTest
@testable import ColonTokenization

final class TextCommitterTests: XCTestCase {
    private let committer = TextCommitter()

    func testCommitsExactRangeAtBeginningMiddleAndEnd() {
        assertCommit(
            document: ":fire suffix",
            token: ":fire",
            replacement: "🔥",
            expectedDocument: "🔥 suffix"
        )
        assertCommit(
            document: "prefix :fire suffix",
            token: ":fire",
            replacement: "🔥",
            expectedDocument: "prefix 🔥 suffix"
        )
        assertCommit(
            document: "prefix :fire",
            token: ":fire",
            replacement: "🔥",
            expectedDocument: "prefix 🔥"
        )
    }

    func testCommitsAfterUnicodeUsingUTF16DocumentRange() {
        assertCommit(
            document: "😀 é :wave tail",
            token: ":wave",
            replacement: "👋🏽",
            expectedDocument: "😀 é 👋🏽 tail"
        )
    }

    func testClosingColonRangeLeavesNoShortcodeCharacters() {
        assertCommit(
            document: "hello :fire:",
            token: ":fire:",
            query: "fire",
            replacement: "🔥",
            expectedDocument: "hello 🔥"
        )
    }

    func testChangedTokenAndRangeAreRejectedWithoutEditing() {
        let changedToken = FakeCommitClient(document: ":firm", caretLocation: 5)
        let tokenOutcome = committer.commit(
            TextCommitExpectation(
                normalizedQuery: "fire",
                documentRange: NSRange(location: 0, length: 5),
                replacementText: "🔥"
            ),
            to: changedToken
        )
        XCTAssertEqual(tokenOutcome, .rejected(.tokenMismatch))
        XCTAssertEqual(changedToken.document, ":firm")
        XCTAssertTrue(changedToken.replacements.isEmpty)

        let movedToken = FakeCommitClient(document: "x :fire", caretLocation: 7)
        let rangeOutcome = committer.commit(
            TextCommitExpectation(
                normalizedQuery: "fire",
                documentRange: NSRange(location: 0, length: 5),
                replacementText: "🔥"
            ),
            to: movedToken
        )
        XCTAssertEqual(rangeOutcome, .rejected(.rangeMismatch))
        XCTAssertEqual(movedToken.document, "x :fire")
        XCTAssertTrue(movedToken.replacements.isEmpty)
    }

    func testRejectsTokenBeginningAtTruncatedContextBoundary() {
        let document = "xx:" + String(repeating: "a", count: 255)
        let client = FakeCommitClient(document: document, caretLocation: (document as NSString).length)
        let expectedRange = NSRange(location: 2, length: 256)

        let outcome = committer.commit(
            TextCommitExpectation(
                normalizedQuery: String(repeating: "a", count: 255),
                documentRange: expectedRange,
                replacementText: "🔥"
            ),
            to: client
        )

        XCTAssertEqual(outcome, .rejected(.tokenMismatch))
        XCTAssertEqual(client.document, document)
        XCTAssertTrue(client.replacements.isEmpty)
    }

    func testSelectionAndEmptyReplacementAreRejected() {
        let selectedClient = FakeCommitClient(
            document: ":fire",
            selectedRange: NSRange(location: 0, length: 5)
        )
        let expectation = TextCommitExpectation(
            normalizedQuery: "fire",
            documentRange: NSRange(location: 0, length: 5),
            replacementText: "🔥"
        )
        XCTAssertEqual(
            committer.commit(expectation, to: selectedClient),
            .rejected(.contextUnavailable)
        )

        let emptyClient = FakeCommitClient(document: ":fire", caretLocation: 5)
        XCTAssertEqual(
            committer.commit(
                TextCommitExpectation(
                    normalizedQuery: "fire",
                    documentRange: NSRange(location: 0, length: 5),
                    replacementText: ""
                ),
                to: emptyClient
            ),
            .rejected(.invalidReplacementText)
        )
        XCTAssertEqual(emptyClient.document, ":fire")
    }

    private func assertCommit(
        document: String,
        token: String,
        query: String? = nil,
        replacement: String,
        expectedDocument: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let documentString = document as NSString
        let tokenRange = documentString.range(of: token)
        let client = FakeCommitClient(
            document: document,
            caretLocation: NSMaxRange(tokenRange)
        )
        let normalizedQuery = query ?? String(token.dropFirst())
        let outcome = committer.commit(
            TextCommitExpectation(
                normalizedQuery: normalizedQuery,
                documentRange: tokenRange,
                replacementText: replacement
            ),
            to: client
        )

        XCTAssertEqual(
            outcome,
            .committed(replacementRange: tokenRange),
            file: file,
            line: line
        )
        XCTAssertEqual(client.document, expectedDocument, file: file, line: line)
        XCTAssertEqual(client.replacements.count, 1, file: file, line: line)
    }
}

private final class FakeCommitClient: TextCommitClient {
    private(set) var document: String
    private(set) var replacements: [(text: String, range: NSRange)] = []
    var selectedRange: NSRange

    init(document: String, caretLocation: Int) {
        self.document = document
        selectedRange = NSRange(location: caretLocation, length: 0)
    }

    init(document: String, selectedRange: NSRange) {
        self.document = document
        self.selectedRange = selectedRange
    }

    func substring(in proposedRange: NSRange) -> TextClientSubstring? {
        let utf16Document = document as NSString
        guard proposedRange.location != NSNotFound,
              proposedRange.location >= 0,
              proposedRange.length >= 0,
              NSMaxRange(proposedRange) <= utf16Document.length
        else {
            return nil
        }
        return TextClientSubstring(
            text: utf16Document.substring(with: proposedRange),
            actualRange: proposedRange
        )
    }

    func replaceText(with text: String, replacementRange: NSRange) {
        replacements.append((text, replacementRange))
        document = (document as NSString).replacingCharacters(
            in: replacementRange,
            with: text
        )
        selectedRange = NSRange(
            location: replacementRange.location + (text as NSString).length,
            length: 0
        )
    }
}
