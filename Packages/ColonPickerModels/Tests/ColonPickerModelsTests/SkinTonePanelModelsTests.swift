import ColonModels
import XCTest
@testable import ColonPickerModels

final class SkinTonePanelModelsTests: XCTestCase {
    func testCycleIndexForEveryVariantCount() {
        XCTAssertEqual(SkinToneCycle.nextIndex(after: 0, count: 0), 0)
        for count in 1...12 {
            for index in 0..<count {
                XCTAssertEqual(SkinToneCycle.nextIndex(after: index, count: count), (index + 1) % count)
            }
        }
    }

    func testAccessibilityLabelsDescribeOfficialToneModifiers() {
        XCTAssertEqual(SkinTonePanelViewModel.accessibilityLabel(for: "👋"), "default skin tone")
        XCTAssertEqual(SkinTonePanelViewModel.accessibilityLabel(for: "👋🏻"), "light skin tone")
        XCTAssertEqual(SkinTonePanelViewModel.accessibilityLabel(for: "👋🏽"), "medium skin tone")
        XCTAssertEqual(
            SkinTonePanelViewModel.accessibilityLabel(for: "🫱🏽‍🫲🏿"),
            "medium skin tone, dark skin tone"
        )
    }

    func testOverlaySemanticSnapshotIncludesSelectionAndContrast() {
        let base = CandidateSelection(
            context: AutocompleteTokenContext(
                sessionID: AutocompleteSessionID(rawValue: "test"),
                tokenID: "token",
                normalizedQuery: "wave",
                replacementRange: NSRange(location: 0, length: 5)
            ),
            candidates: [TestCandidateFactory.wave],
            selectedIndex: 0
        )
        let selection = SkinToneSelection(
            baseSelection: base,
            variants: ["👋", "👋🏻", "👋🏽"],
            selectedIndex: 1
        )
        let model = SkinTonePanelViewModel(
            selection: selection,
            appearance: .dark,
            accessibility: CandidatePanelAccessibility(reduceMotion: true, increaseContrast: true)
        )

        XCTAssertEqual(
            model.snapshotDescription,
            """
            appearance=dark|increaseContrast=true
            normal|👋|default skin tone
            selected|👋🏻|light skin tone
            normal|👋🏽|medium skin tone
            """
        )
    }
}

private enum TestCandidateFactory {
    static let wave: EmojiCandidate = {
        let entry = EmojiEntry(
            id: EmojiID(rawValue: "wave"),
            emoji: "👋",
            canonicalName: "waving hand",
            canonicalAlias: "wave",
            alternateAliases: [],
            tags: [],
            category: .peopleAndBody,
            sortOrder: 0,
            skinToneVariants: ["👋", "👋🏻", "👋🏽"]
        )
        return EmojiCandidate(
            id: entry.id,
            entry: entry,
            renderedEmoji: "👋",
            matchedTerm: "wave",
            matchKind: .exactCanonical,
            score: 10_000
        )
    }()
}
