import ColonModels
import XCTest
@testable import ColonPickerModels

final class CandidatePanelModelsTests: XCTestCase {
    func testViewModelProjectsSixRowsOverflowSelectionAndHints() {
        let selection = makeSelection(count: 8, selectedIndex: 5)
        let model = CandidatePanelViewModel(
            selection: selection,
            visibleRowCount: 6,
            size: .standard,
            appearance: .system,
            accessibility: CandidatePanelAccessibility(reduceMotion: false, increaseContrast: false)
        )

        XCTAssertEqual(model.rows.count, 8)
        XCTAssertEqual(model.visibleRowCount, 6)
        XCTAssertEqual(model.contentHeight, 216)
        XCTAssertEqual(model.selectedRowID?.rawValue, "id-5")
        XCTAssertNil(model.rows[0].matchingHint)
        XCTAssertEqual(model.rows[1].matchingHint, "hint-1")
    }

    func testSemanticSnapshotsCoverLightDarkLongLabelsNoHintAndHighContrast() {
        let selection = CandidateSelection(
            context: context,
            candidates: [
                candidate(index: 0, name: "a very long canonical label that must truncate", hint: nil),
                candidate(index: 1, name: "second", hint: "query_hint"),
            ],
            selectedIndex: 1
        )

        let light = CandidatePanelViewModel(
            selection: selection,
            visibleRowCount: 6,
            size: .compact,
            appearance: .light,
            accessibility: CandidatePanelAccessibility(reduceMotion: false, increaseContrast: false)
        )
        XCTAssertEqual(
            light.snapshotDescription,
            """
            appearance=light|rows=6|width=280|rowHeight=32|reduceMotion=false|increaseContrast=false
            normal|🙂|:alias_0|a very long canonical label that must truncate|hint=none
            selected|🙂|:alias_1|second|hint=query_hint
            """
        )

        let darkHighContrast = CandidatePanelViewModel(
            selection: selection,
            visibleRowCount: 6,
            size: .large,
            appearance: .dark,
            accessibility: CandidatePanelAccessibility(reduceMotion: true, increaseContrast: true)
        )
        XCTAssertTrue(darkHighContrast.snapshotDescription.hasPrefix(
            "appearance=dark|rows=6|width=390|rowHeight=58|reduceMotion=true|increaseContrast=true"
        ))
    }

    func testPositioningPrefersAboveThenFlipsAndClampsAtScreenEdges() {
        let screen = PanelRect(x: 0, y: 0, width: 1440, height: 900)
        let size = PanelSize(width: 340, height: 288)

        XCTAssertEqual(
            CandidatePanelPositioner.frame(
                anchor: PanelRect(x: 500, y: 400, width: 2, height: 20),
                panelSize: size,
                visibleScreen: screen
            ),
            PanelRect(x: 500, y: 426, width: 340, height: 288)
        )
        XCTAssertEqual(
            CandidatePanelPositioner.frame(
                anchor: PanelRect(x: 500, y: 100, width: 2, height: 20),
                panelSize: size,
                visibleScreen: screen
            ),
            PanelRect(x: 500, y: 126, width: 340, height: 288)
        )
        XCTAssertEqual(
            CandidatePanelPositioner.frame(
                anchor: PanelRect(x: 1_350, y: 880, width: 2, height: 20),
                panelSize: size,
                visibleScreen: screen
            ),
            PanelRect(x: 1_100, y: 586, width: 340, height: 288)
        )
    }

    func testCaretValidationRejectsMissingGeometryAndSupportsSecondaryDisplays() {
        let screens = [PanelRect(x: 0, y: 0, width: 1440, height: 900),
                       PanelRect(x: -1920, y: -200, width: 1920, height: 1080)]
        XCTAssertNil(CaretAnchorResolver.validated(PanelRect(x: 0, y: 0, width: 0, height: 0), screens: screens))
        XCTAssertNil(CaretAnchorResolver.validated(PanelRect(x: .nan, y: 100, width: 1, height: 20), screens: screens))
        XCTAssertNil(CaretAnchorResolver.validated(PanelRect(x: 5000, y: 100, width: 1, height: 20), screens: screens))
        let rect = CaretAnchorResolver.validated(PanelRect(x: -500, y: 200, width: 0, height: 20), screens: screens)
        XCTAssertEqual(rect, PanelRect(x: -500, y: 200, width: 1, height: 20))
        XCTAssertEqual(CaretAnchorResolver.validated(PanelRect(x: 600, y: 400, width: -1, height: 20), screens: screens),
                       PanelRect(x: 599, y: 400, width: 1, height: 20))
        XCTAssertEqual(CandidatePanelPositioner.frame(
            anchor: rect!, panelSize: PanelSize(width: 320, height: 216), visibleScreen: screens[1]),
            PanelRect(x: -500, y: 226, width: 320, height: 216))
    }

    func testCorrectionRowsHaveNoActiveSelectionAndShowPrompt() {
        let model = CandidatePanelViewModel(
            selection: makeSelection(count: 8, selectedIndex: 3), visibleRowCount: 6,
            size: .standard, appearance: .system,
            accessibility: CandidatePanelAccessibility(reduceMotion: false, increaseContrast: false),
            correctionMessage: "Keep typing an emoji name")
        XCTAssertNil(model.selectedRowID)
        XCTAssertEqual(model.rows.count, 8)
        XCTAssertEqual(model.contentHeight, 244)
        XCTAssertEqual(model.correctionMessage, "Keep typing an emoji name")
    }

    func testMouseSelectionSessionGateRejectsStaleCallbacks() {
        var gate = CandidatePanelSessionGate()
        gate.begin(token: "current")
        XCTAssertTrue(gate.accepts(token: "current"))
        XCTAssertFalse(gate.accepts(token: "stale"))
        gate.invalidate()
        XCTAssertFalse(gate.accepts(token: "current"))
    }

    func testPresentationStateIssuesScrollRequestForEveryInPlaceUpdate() {
        var state = CandidatePanelPresentationState(
            model: makeViewModel(selectedIndex: 0)
        )

        XCTAssertEqual(state.scrollTarget.rowID?.rawValue, "id-0")
        XCTAssertEqual(state.scrollTarget.revision, 0)

        state.update(model: makeViewModel(selectedIndex: 6))
        XCTAssertEqual(state.scrollTarget.rowID?.rawValue, "id-6")
        XCTAssertEqual(state.scrollTarget.revision, 1)

        state.update(model: makeViewModel(selectedIndex: 6))
        XCTAssertEqual(state.scrollTarget.rowID?.rawValue, "id-6")
        XCTAssertEqual(state.scrollTarget.revision, 2)
    }

    private var context: AutocompleteTokenContext {
        AutocompleteTokenContext(
            sessionID: AutocompleteSessionID(rawValue: "test"),
            tokenID: "token",
            normalizedQuery: "a",
            replacementRange: NSRange(location: 0, length: 2)
        )
    }

    private func makeSelection(count: Int, selectedIndex: Int) -> CandidateSelection {
        CandidateSelection(
            context: context,
            candidates: (0..<count).map { candidate(index: $0, name: "name-\($0)", hint: $0 == 0 ? nil : "hint-\($0)") },
            selectedIndex: selectedIndex
        )
    }

    private func makeViewModel(selectedIndex: Int) -> CandidatePanelViewModel {
        CandidatePanelViewModel(
            selection: makeSelection(count: 10, selectedIndex: selectedIndex),
            visibleRowCount: 6,
            size: .standard,
            appearance: .system,
            accessibility: CandidatePanelAccessibility(
                reduceMotion: false,
                increaseContrast: false
            )
        )
    }

    private func candidate(index: Int, name: String, hint: String?) -> EmojiCandidate {
        let alias = "alias_\(index)"
        let entry = EmojiEntry(
            id: EmojiID(rawValue: "id-\(index)"),
            emoji: "🙂",
            canonicalName: name,
            canonicalAlias: alias,
            alternateAliases: [],
            tags: [],
            category: .smileysAndEmotion,
            sortOrder: index,
            skinToneVariants: ["🙂"]
        )
        return EmojiCandidate(
            id: entry.id,
            entry: entry,
            renderedEmoji: "🙂",
            matchedTerm: hint ?? alias,
            matchKind: hint == nil ? .exactCanonical : .tagPrefix,
            score: 8_000 - index
        )
    }
}
