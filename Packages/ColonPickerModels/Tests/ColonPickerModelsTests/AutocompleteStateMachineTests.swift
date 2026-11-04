import ColonModels
import XCTest
@testable import ColonPickerModels

final class AutocompleteStateMachineTests: XCTestCase {
    private let session = AutocompleteSessionID(rawValue: "session-a")

    func testColonAndCandidateTransitionsAutoSelectFirstResult() {
        var machine = AutocompleteStateMachine()
        let context = token(query: "")

        XCTAssertEqual(machine.handle(.textMutation(.colonOnly(context))), [.hidePanel])
        XCTAssertEqual(machine.state, .trackingColon(context))

        let results = [candidate("first"), candidate("second")]
        let effects = machine.handle(.textMutation(.active(context: token(query: "f"), candidates: results)))

        guard case .candidates(let selection) = machine.state else {
            return XCTFail("Expected candidates state")
        }
        XCTAssertEqual(selection.selectedIndex, 0)
        XCTAssertEqual(selection.selectedCandidate.id.rawValue, "first")
        XCTAssertEqual(effects, [.showCandidates(selection)])
    }

    func testUpAndDownWrapCyclically() {
        var machine = machineWithCandidates([candidate("first"), candidate("second"), candidate("third")])

        _ = machine.handle(.up)
        XCTAssertEqual(selectedID(machine), "third")
        _ = machine.handle(.down)
        XCTAssertEqual(selectedID(machine), "first")
        _ = machine.handle(.down)
        XCTAssertEqual(selectedID(machine), "second")
    }

    func testSelectionIsPreservedByEmojiIDWhenResultsUpdate() {
        let first = candidate("first")
        let second = candidate("second")
        var machine = machineWithCandidates([first, second])
        _ = machine.handle(.down)

        _ = machine.handle(
            .textMutation(.active(context: token(query: "fi"), candidates: [second, first]))
        )
        XCTAssertEqual(selectedID(machine), "second")

        _ = machine.handle(
            .textMutation(.active(context: token(query: "fir"), candidates: [first]))
        )
        XCTAssertEqual(selectedID(machine), "first")
    }

    func testNoResultsKeepPreviousCandidatesVisibleAndLaterMatchingEditRestoresResults() {
        var machine = machineWithCandidates([candidate("first")])
        let noResultsContext = token(query: "zzz")
        guard case .candidates(let previousSelection) = machine.state else {
            return XCTFail("Expected initial candidates")
        }

        XCTAssertEqual(
            machine.handle(.textMutation(.active(context: noResultsContext, candidates: []))),
            [.showCorrection(context: noResultsContext, previousSelection: previousSelection)]
        )
        XCTAssertEqual(
            machine.state,
            .correcting(context: noResultsContext, previousSelection: previousSelection)
        )

        let restored = [candidate("first")]
        _ = machine.handle(.textMutation(.active(context: token(query: "f"), candidates: restored)))
        XCTAssertEqual(selectedID(machine), "first")
    }

    func testCorrectionPassesThroughKeysAndRejectsStaleMouseCommit() {
        var machine = machineWithCandidates([candidate("first"), candidate("second")])
        let staleContext = token(query: "typo")
        guard case .candidates(let previousSelection) = machine.state else {
            return XCTFail("Expected initial candidates")
        }
        XCTAssertEqual(
            machine.handle(.textMutation(.active(context: staleContext, candidates: []))),
            [.showCorrection(context: staleContext, previousSelection: previousSelection)]
        )
        XCTAssertEqual(machine.handle(.enter), [.passThrough(.enter)])
        XCTAssertEqual(machine.handle(.tab), [.passThrough(.tab)])
        XCTAssertTrue(machine.handle(.mouseSelection(EmojiID(rawValue: "first"))).isEmpty)
        XCTAssertEqual(
            machine.state,
            .correcting(context: staleContext, previousSelection: previousSelection)
        )

        let bareColon = token(query: "")
        XCTAssertEqual(
            machine.handle(.textMutation(.colonOnly(bareColon))),
            [.showCorrection(context: bareColon, previousSelection: previousSelection)]
        )
    }

    func testEscapeDismissesCorrectionUntilTokenBoundary() {
        var machine = machineWithCandidates([candidate("first")])
        let typo = token(query: "typo")
        _ = machine.handle(.textMutation(.active(context: typo, candidates: [])))

        XCTAssertEqual(machine.handle(.escape), [.hidePanel])
        XCTAssertEqual(machine.state, .dismissed(typo))
        XCTAssertTrue(
            machine.handle(.textMutation(.active(context: token(query: "f"), candidates: [candidate("first")]))).isEmpty
        )
        XCTAssertEqual(machine.state, .dismissed(typo))

        XCTAssertEqual(machine.handle(.boundary(.space)), [.hidePanel, .passThrough(.space)])
        let nextToken = token(tokenID: "token-b", query: "f")
        _ = machine.handle(.textMutation(.active(context: nextToken, candidates: [candidate("first")])) )
        XCTAssertEqual(selectedID(machine), "first")
    }

    func testEscapeSuppressesSameTokenUntilBoundaryAndLeavesTextUntouched() {
        var machine = machineWithCandidates([candidate("first")])
        let context = token(query: "f")

        XCTAssertEqual(machine.handle(.escape), [.hidePanel])
        XCTAssertEqual(machine.state, .dismissed(context))
        XCTAssertTrue(
            machine.handle(.textMutation(.active(context: token(query: "fi"), candidates: [candidate("first")]))).isEmpty
        )
        XCTAssertEqual(machine.state, .dismissed(context))

        XCTAssertEqual(machine.handle(.boundary(.space)), [.hidePanel, .passThrough(.space)])
        let newToken = token(tokenID: "token-b", query: "f")
        _ = machine.handle(.textMutation(.active(context: newToken, candidates: [candidate("first")])))
        XCTAssertEqual(selectedID(machine), "first")
    }

    func testSpaceAndPunctuationEndUIAndPassThrough() {
        for input in [PassthroughInput.space, .punctuation] {
            var machine = machineWithCandidates([candidate("first")])
            XCTAssertEqual(machine.handle(.boundary(input)), [.hidePanel, .passThrough(input)])
            XCTAssertEqual(machine.state, .idle)
        }
    }

    func testStaleSessionMutationResetsAndIsIgnored() {
        var machine = machineWithCandidates([candidate("first")])
        let staleContext = AutocompleteTokenContext(
            sessionID: AutocompleteSessionID(rawValue: "session-b"),
            tokenID: "token-b",
            normalizedQuery: "f",
            replacementRange: NSRange(location: 0, length: 2)
        )

        XCTAssertEqual(
            machine.handle(.textMutation(.active(context: staleContext, candidates: [candidate("second")]))),
            [.hidePanel]
        )
        XCTAssertEqual(machine.state, .idle)
    }

    func testClosingColonCommitsOnlyWhenMatchesExist() {
        let result = candidate("first")
        var machine = machineWithCandidates([result])

        let effects = machine.handle(
            .textMutation(.closingColon(context: token(query: "f"), candidates: [result]))
        )
        guard case .committing(let request) = machine.state else {
            return XCTFail("Expected committing state")
        }
        XCTAssertEqual(request.trigger, .closingColon)
        XCTAssertEqual(effects, [.hidePanel, .commit(request)])

        var noMatchMachine = AutocompleteStateMachine()
        XCTAssertEqual(
            noMatchMachine.handle(
                .textMutation(.closingColon(context: token(query: "zzz"), candidates: []))
            ),
            [.hidePanel]
        )
        XCTAssertEqual(noMatchMachine.state, .noResultsHidden(token(query: "zzz")))
    }

    func testClosingColonCommitsPreviouslySelectedSkinTone() {
        let wave = candidate(
            "wave",
            emoji: "👋",
            variants: ["👋", "👋🏻", "👋🏽"]
        )
        let originalContext = token(query: "wave")
        var machine = AutocompleteStateMachine(activeSessionID: session)
        _ = machine.handle(.textMutation(.active(context: originalContext, candidates: [wave])))
        _ = machine.handle(.tab)
        guard case .skinTones(let toneSelection) = machine.state else {
            return XCTFail("Expected tone overlay")
        }
        XCTAssertEqual(toneSelection.selectedVariant, "👋🏻")

        let closingColonContext = AutocompleteTokenContext(
            sessionID: session,
            tokenID: "token-a",
            normalizedQuery: "wave",
            replacementRange: NSRange(
                location: originalContext.replacementRange.location,
                length: originalContext.replacementRange.length + 1
            )
        )
        let effects = machine.handle(
            .textMutation(.closingColon(context: closingColonContext, candidates: [wave]))
        )
        guard case .committing(let request) = machine.state else {
            return XCTFail("Expected closing-colon commit")
        }
        XCTAssertEqual(request.context, closingColonContext)
        XCTAssertEqual(request.candidate.id, wave.id)
        XCTAssertEqual(request.renderedEmoji, "👋🏻")
        XCTAssertEqual(request.trigger, .skinTone)
        XCTAssertEqual(effects, [.hidePanel, .commit(request)])
    }

    func testEnterMouseAndCommitCompletionTransitions() {
        var machine = machineWithCandidates([candidate("first")])
        let effects = machine.handle(.enter)
        guard case .committing(let request) = machine.state else {
            return XCTFail("Expected committing state")
        }
        XCTAssertEqual(request.trigger, .enter)
        XCTAssertEqual(effects, [.hidePanel, .commit(request)])
        XCTAssertEqual(machine.handle(.commitCompleted), [.hidePanel])
        XCTAssertEqual(machine.state, .idle)

        var mouseMachine = machineWithCandidates([candidate("first"), candidate("second")])
        _ = mouseMachine.handle(.mouseSelection(EmojiID(rawValue: "second")))
        guard case .committing(let request) = mouseMachine.state else {
            return XCTFail("Expected mouse commit")
        }
        XCTAssertEqual(request.candidate.id.rawValue, "second")
        XCTAssertEqual(request.trigger, .mouse)
    }

    func testTabWithoutSkinTonesPassesThroughAndNeverCommits() {
        var machine = machineWithCandidates([candidate("first")])

        XCTAssertEqual(
            machine.handle(.tab),
            [.hidePanel, .passThrough(.tab)]
        )
        XCTAssertEqual(machine.state, .idle)
    }

    func testSkinToneStateSupportsCyclicNavigationCancelAndCommit() {
        var machine = machineWithCandidates([candidate("wave", emoji: "👋")])
        _ = machine.handle(.showSkinTones(["👋", "👋🏻", "👋🏽"]))
        guard case .skinTones(let initial) = machine.state else {
            return XCTFail("Expected skin tones")
        }
        XCTAssertEqual(initial.selectedIndex, 0)

        _ = machine.handle(.up)
        guard case .skinTones(let wrapped) = machine.state else {
            return XCTFail("Expected skin tones")
        }
        XCTAssertEqual(wrapped.selectedVariant, "👋🏽")

        _ = machine.handle(.enter)
        guard case .committing(let request) = machine.state else {
            return XCTFail("Expected commit")
        }
        XCTAssertEqual(request.renderedEmoji, "👋🏽")
        XCTAssertEqual(request.trigger, .skinTone)

        var cancelMachine = machineWithCandidates([candidate("wave", emoji: "👋")])
        _ = cancelMachine.handle(.showSkinTones(["👋", "👋🏻"]))
        _ = cancelMachine.handle(.cancelSkinTones)
        XCTAssertEqual(selectedID(cancelMachine), "wave")
    }

    func testIdenticalTextRefreshPreservesSkinToneSelection() {
        let wave = candidate(
            "wave",
            emoji: "👋",
            variants: ["👋", "👋🏻", "👋🏽"]
        )
        let context = token(query: "f")
        var machine = AutocompleteStateMachine(activeSessionID: session)
        _ = machine.handle(.textMutation(.active(context: context, candidates: [wave])))
        _ = machine.handle(.tab)
        guard case .skinTones(let selectedTone) = machine.state else {
            return XCTFail("Expected tone overlay")
        }
        XCTAssertEqual(selectedTone.selectedVariant, "👋🏻")

        XCTAssertEqual(
            machine.handle(.textMutation(.active(context: context, candidates: [wave]))),
            [.showSkinTones(selectedTone)]
        )
        XCTAssertEqual(machine.state, .skinTones(selectedTone))
        _ = machine.handle(.enter)
        guard case .committing(let request) = machine.state else {
            return XCTFail("Expected selected tone commit")
        }
        XCTAssertEqual(request.renderedEmoji, "👋🏻")
        XCTAssertEqual(request.trigger, .skinTone)
    }

    func testTabOpensAtNextToneCyclesAndEscapeReturnsToMainPanel() {
        let wave = candidate(
            "wave",
            emoji: "👋",
            variants: ["👋", "👋🏻", "👋🏽"]
        )
        var machine = machineWithCandidates([wave])

        _ = machine.handle(.tab)
        guard case .skinTones(let firstTone) = machine.state else {
            return XCTFail("Expected tone overlay")
        }
        XCTAssertEqual(firstTone.selectedVariant, "👋🏻")

        _ = machine.handle(.tab)
        guard case .skinTones(let secondTone) = machine.state else {
            return XCTFail("Expected tone overlay")
        }
        XCTAssertEqual(secondTone.selectedVariant, "👋🏽")

        let effects = machine.handle(.escape)
        guard case .candidates(let selection) = machine.state else {
            return XCTFail("Expected return to candidates")
        }
        XCTAssertEqual(effects, [.showCandidates(selection)])
    }

    func testToneMouseSelectionCommitsSelectedVariant() {
        let wave = candidate(
            "wave",
            emoji: "👋",
            variants: ["👋", "👋🏻", "👋🏽"]
        )
        var machine = machineWithCandidates([wave])
        _ = machine.handle(.tab)

        let effects = machine.handle(.skinToneSelection(2))
        guard case .committing(let request) = machine.state else {
            return XCTFail("Expected tone commit")
        }
        XCTAssertEqual(request.renderedEmoji, "👋🏽")
        XCTAssertEqual(effects, [.hidePanel, .commit(request)])
    }

    func testUnhandledKeysPassThroughAcrossHiddenStates() {
        var machine = AutocompleteStateMachine()
        XCTAssertEqual(machine.handle(.up), [.passThrough(.up)])
        XCTAssertEqual(machine.handle(.down), [.passThrough(.down)])
        XCTAssertEqual(machine.handle(.enter), [.passThrough(.enter)])
        XCTAssertEqual(machine.handle(.tab), [.passThrough(.tab)])
        XCTAssertEqual(machine.handle(.escape), [.passThrough(.escape)])
    }

    private func machineWithCandidates(_ candidates: [EmojiCandidate]) -> AutocompleteStateMachine {
        var machine = AutocompleteStateMachine(activeSessionID: session)
        _ = machine.handle(.textMutation(.active(context: token(query: "f"), candidates: candidates)))
        return machine
    }

    private func selectedID(_ machine: AutocompleteStateMachine) -> String? {
        guard case .candidates(let selection) = machine.state else {
            return nil
        }
        return selection.selectedCandidate.id.rawValue
    }

    private func token(tokenID: String = "token-a", query: String) -> AutocompleteTokenContext {
        AutocompleteTokenContext(
            sessionID: session,
            tokenID: tokenID,
            normalizedQuery: query,
            replacementRange: NSRange(location: 0, length: query.utf16.count + 1)
        )
    }

    private func candidate(
        _ id: String,
        emoji: String = "🙂",
        variants: [String]? = nil
    ) -> EmojiCandidate {
        let entry = EmojiEntry(
            id: EmojiID(rawValue: id),
            emoji: emoji,
            canonicalName: id,
            canonicalAlias: id,
            alternateAliases: [],
            tags: [],
            category: .peopleAndBody,
            sortOrder: 0,
            skinToneVariants: variants ?? [emoji]
        )
        return EmojiCandidate(
            id: entry.id,
            entry: entry,
            renderedEmoji: emoji,
            matchedTerm: id,
            matchKind: .canonicalPrefix,
            score: 8_000
        )
    }
}
