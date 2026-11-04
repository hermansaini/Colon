import ColonModels
import Foundation

public struct AutocompleteSessionID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AutocompleteTokenContext: Equatable, Sendable {
    public let sessionID: AutocompleteSessionID
    public let tokenID: String
    public let normalizedQuery: String
    public let replacementRange: NSRange

    public init(
        sessionID: AutocompleteSessionID,
        tokenID: String,
        normalizedQuery: String,
        replacementRange: NSRange
    ) {
        self.sessionID = sessionID
        self.tokenID = tokenID
        self.normalizedQuery = normalizedQuery
        self.replacementRange = replacementRange
    }
}

public struct CandidateSelection: Equatable, Sendable {
    public let context: AutocompleteTokenContext
    public let candidates: [EmojiCandidate]
    public let selectedIndex: Int

    public var selectedCandidate: EmojiCandidate {
        candidates[selectedIndex]
    }

    public init(
        context: AutocompleteTokenContext,
        candidates: [EmojiCandidate],
        selectedIndex: Int = 0
    ) {
        precondition(candidates.isEmpty == false)
        self.context = context
        self.candidates = candidates
        self.selectedIndex = min(max(0, selectedIndex), candidates.count - 1)
    }
}

public struct SkinToneSelection: Equatable, Sendable {
    public let baseSelection: CandidateSelection
    public let variants: [String]
    public let selectedIndex: Int

    public var selectedVariant: String {
        variants[selectedIndex]
    }

    public init(baseSelection: CandidateSelection, variants: [String], selectedIndex: Int = 0) {
        precondition(variants.isEmpty == false)
        self.baseSelection = baseSelection
        self.variants = variants
        self.selectedIndex = min(max(0, selectedIndex), variants.count - 1)
    }
}

public enum CommitTrigger: String, Equatable, Sendable {
    case enter
    case closingColon
    case mouse
    case skinTone
}

public struct CommitRequest: Equatable, Sendable {
    public let context: AutocompleteTokenContext
    public let candidate: EmojiCandidate
    public let renderedEmoji: String
    public let trigger: CommitTrigger

    public init(
        context: AutocompleteTokenContext,
        candidate: EmojiCandidate,
        renderedEmoji: String,
        trigger: CommitTrigger
    ) {
        self.context = context
        self.candidate = candidate
        self.renderedEmoji = renderedEmoji
        self.trigger = trigger
    }
}

public enum AutocompleteState: Equatable, Sendable {
    case idle
    case trackingColon(AutocompleteTokenContext)
    case candidates(CandidateSelection)
    case noResultsHidden(AutocompleteTokenContext)
    case correcting(context: AutocompleteTokenContext, previousSelection: CandidateSelection)
    case skinTones(SkinToneSelection)
    case dismissed(AutocompleteTokenContext)
    case committing(CommitRequest)
}

public enum AutocompleteTextMutation: Equatable, Sendable {
    case inactive(sessionID: AutocompleteSessionID)
    case colonOnly(AutocompleteTokenContext)
    case active(context: AutocompleteTokenContext, candidates: [EmojiCandidate])
    case closingColon(context: AutocompleteTokenContext, candidates: [EmojiCandidate])

    var sessionID: AutocompleteSessionID {
        switch self {
        case .inactive(let sessionID):
            sessionID
        case .colonOnly(let context), .active(let context, _), .closingColon(let context, _):
            context.sessionID
        }
    }
}

public enum PassthroughInput: String, Equatable, Sendable {
    case up
    case down
    case enter
    case tab
    case escape
    case space
    case punctuation
}

public enum AutocompleteEvent: Equatable, Sendable {
    case textMutation(AutocompleteTextMutation)
    case up
    case down
    case enter
    case tab
    case escape
    case boundary(PassthroughInput)
    case sessionChanged(AutocompleteSessionID)
    case mouseSelection(EmojiID)
    case skinToneSelection(Int)
    case showSkinTones([String])
    case cancelSkinTones
    case commitCompleted
}

public enum AutocompleteEffect: Equatable, Sendable {
    case showCandidates(CandidateSelection)
    case showCorrection(context: AutocompleteTokenContext, previousSelection: CandidateSelection)
    case showSkinTones(SkinToneSelection)
    case hidePanel
    case commit(CommitRequest)
    case passThrough(PassthroughInput)
}

public struct AutocompleteStateMachine: Sendable {
    public private(set) var activeSessionID: AutocompleteSessionID?
    public private(set) var state: AutocompleteState

    public init(
        activeSessionID: AutocompleteSessionID? = nil,
        state: AutocompleteState = .idle
    ) {
        self.activeSessionID = activeSessionID
        self.state = state
    }

    @discardableResult
    public mutating func handle(_ event: AutocompleteEvent) -> [AutocompleteEffect] {
        switch event {
        case .textMutation(let mutation):
            return handleTextMutation(mutation)
        case .up:
            return moveSelection(by: -1, passthrough: .up)
        case .down:
            return moveSelection(by: 1, passthrough: .down)
        case .enter:
            return commitSelection(trigger: .enter, passthrough: .enter)
        case .tab:
            return handleTab()
        case .escape:
            return handleEscape()
        case .boundary(let input):
            state = .idle
            return [.hidePanel, .passThrough(input)]
        case .sessionChanged(let sessionID):
            activeSessionID = sessionID
            state = .idle
            return [.hidePanel]
        case .mouseSelection(let emojiID):
            return handleMouseSelection(emojiID)
        case .skinToneSelection(let selectedIndex):
            return handleSkinToneSelection(selectedIndex)
        case .showSkinTones(let variants):
            return showSkinTones(variants)
        case .cancelSkinTones:
            return cancelSkinTones()
        case .commitCompleted:
            state = .idle
            return [.hidePanel]
        }
    }

    private mutating func handleTextMutation(
        _ mutation: AutocompleteTextMutation
    ) -> [AutocompleteEffect] {
        if let activeSessionID, activeSessionID != mutation.sessionID {
            state = .idle
            return [.hidePanel]
        }
        activeSessionID = mutation.sessionID

        switch mutation {
        case .inactive:
            state = .idle
            return [.hidePanel]
        case .colonOnly(let context):
            guard isSuppressed(context) == false else {
                return []
            }
            if let previousSelection = visibleSelection(for: context) {
                state = .correcting(context: context, previousSelection: previousSelection)
                return [.showCorrection(context: context, previousSelection: previousSelection)]
            }
            state = .trackingColon(context)
            return [.hidePanel]
        case .active(let context, let candidates):
            guard isSuppressed(context) == false else {
                return []
            }
            if case .skinTones(let selection) = state,
               selection.baseSelection.context == context,
               selection.baseSelection.candidates == candidates
            {
                return [.showSkinTones(selection)]
            }
            return present(candidates: candidates, context: context)
        case .closingColon(let context, let candidates):
            guard isSuppressed(context) == false else {
                return []
            }
            guard candidates.isEmpty == false else {
                return hideResultsOrKeepCorrection(context: context)
            }
            let selection = makeSelection(candidates: candidates, context: context)
            let matchingToneSelection = selectedToneSelection(
                matching: context,
                candidates: candidates
            )
            let selectedCandidate = matchingToneSelection.flatMap { toneSelection in
                candidates.first { $0.id == toneSelection.baseSelection.selectedCandidate.id }
            } ?? selection.selectedCandidate
            let request = CommitRequest(
                context: selection.context,
                candidate: selectedCandidate,
                renderedEmoji: matchingToneSelection?.selectedVariant ?? selection.selectedCandidate.renderedEmoji,
                trigger: matchingToneSelection == nil ? .closingColon : .skinTone
            )
            state = .committing(request)
            return [.hidePanel, .commit(request)]
        }
    }

    private mutating func present(
        candidates: [EmojiCandidate],
        context: AutocompleteTokenContext
    ) -> [AutocompleteEffect] {
        guard candidates.isEmpty == false else {
            return hideResultsOrKeepCorrection(context: context)
        }

        let selection = makeSelection(candidates: candidates, context: context)
        state = .candidates(selection)
        return [.showCandidates(selection)]
    }

    private mutating func hideResultsOrKeepCorrection(
        context: AutocompleteTokenContext
    ) -> [AutocompleteEffect] {
        guard let previousSelection = visibleSelection(for: context) else {
            state = .noResultsHidden(context)
            return [.hidePanel]
        }
        state = .correcting(context: context, previousSelection: previousSelection)
        return [.showCorrection(context: context, previousSelection: previousSelection)]
    }

    private func visibleSelection(for context: AutocompleteTokenContext) -> CandidateSelection? {
        let selection: CandidateSelection
        switch state {
        case .candidates(let value):
            selection = value
        case .skinTones(let value):
            selection = value.baseSelection
        case .correcting(_, let previousSelection):
            selection = previousSelection
        default:
            return nil
        }
        guard isSameToken(selection.context, context) else {
            return nil
        }
        return selection
    }

    private func isSameToken(
        _ lhs: AutocompleteTokenContext,
        _ rhs: AutocompleteTokenContext
    ) -> Bool {
        lhs.sessionID == rhs.sessionID && lhs.tokenID == rhs.tokenID
    }

    private func selectedToneSelection(
        matching context: AutocompleteTokenContext,
        candidates: [EmojiCandidate]
    ) -> SkinToneSelection? {
        guard case .skinTones(let selection) = state,
              hasSameQueryThroughClosingColon(selection.baseSelection.context, context),
              let candidate = candidates.first(where: {
                  $0.id == selection.baseSelection.selectedCandidate.id
              }),
              candidate.entry.skinToneVariants.contains(selection.selectedVariant)
        else {
            return nil
        }
        return selection
    }

    private func hasSameQueryThroughClosingColon(
        _ previous: AutocompleteTokenContext,
        _ current: AutocompleteTokenContext
    ) -> Bool {
        previous.sessionID == current.sessionID
            && previous.tokenID == current.tokenID
            && previous.normalizedQuery == current.normalizedQuery
            && previous.replacementRange.location == current.replacementRange.location
            && current.replacementRange.length >= previous.replacementRange.length
            && current.replacementRange.length <= previous.replacementRange.length + 1
    }

    private func makeSelection(
        candidates: [EmojiCandidate],
        context: AutocompleteTokenContext
    ) -> CandidateSelection {
        let previouslySelectedID: EmojiID?
        switch state {
        case .candidates(let selection):
            previouslySelectedID = selection.selectedCandidate.id
        case .skinTones(let selection):
            previouslySelectedID = selection.baseSelection.selectedCandidate.id
        case .correcting(_, let selection):
            previouslySelectedID = selection.selectedCandidate.id
        default:
            previouslySelectedID = nil
        }
        let selectedIndex = previouslySelectedID.flatMap { selectedID in
            candidates.firstIndex { $0.id == selectedID }
        } ?? 0
        return CandidateSelection(
            context: context,
            candidates: candidates,
            selectedIndex: selectedIndex
        )
    }

    private mutating func moveSelection(
        by offset: Int,
        passthrough: PassthroughInput
    ) -> [AutocompleteEffect] {
        switch state {
        case .candidates(let selection):
            let count = selection.candidates.count
            let selectedIndex = (selection.selectedIndex + offset + count) % count
            let updated = CandidateSelection(
                context: selection.context,
                candidates: selection.candidates,
                selectedIndex: selectedIndex
            )
            state = .candidates(updated)
            return [.showCandidates(updated)]
        case .skinTones(let selection):
            let count = selection.variants.count
            let selectedIndex = (selection.selectedIndex + offset + count) % count
            let updated = SkinToneSelection(
                baseSelection: selection.baseSelection,
                variants: selection.variants,
                selectedIndex: selectedIndex
            )
            state = .skinTones(updated)
            return [.showSkinTones(updated)]
        default:
            return [.passThrough(passthrough)]
        }
    }

    private mutating func commitSelection(
        trigger: CommitTrigger,
        passthrough: PassthroughInput
    ) -> [AutocompleteEffect] {
        let request: CommitRequest
        switch state {
        case .candidates(let selection):
            request = CommitRequest(
                context: selection.context,
                candidate: selection.selectedCandidate,
                renderedEmoji: selection.selectedCandidate.renderedEmoji,
                trigger: trigger
            )
        case .skinTones(let selection):
            request = CommitRequest(
                context: selection.baseSelection.context,
                candidate: selection.baseSelection.selectedCandidate,
                renderedEmoji: selection.selectedVariant,
                trigger: .skinTone
            )
        default:
            return [.passThrough(passthrough)]
        }
        state = .committing(request)
        return [.hidePanel, .commit(request)]
    }

    private mutating func handleEscape() -> [AutocompleteEffect] {
        if case .skinTones(let selection) = state {
            state = .candidates(selection.baseSelection)
            return [.showCandidates(selection.baseSelection)]
        }

        let context: AutocompleteTokenContext
        switch state {
        case .trackingColon(let value), .noResultsHidden(let value), .dismissed(let value):
            context = value
        case .correcting(let value, _):
            context = value
        case .candidates(let selection):
            context = selection.context
        default:
            return [.passThrough(.escape)]
        }
        state = .dismissed(context)
        return [.hidePanel]
    }

    private mutating func handleMouseSelection(_ emojiID: EmojiID) -> [AutocompleteEffect] {
        guard case .candidates(let selection) = state,
              let candidate = selection.candidates.first(where: { $0.id == emojiID })
        else {
            return []
        }
        let request = CommitRequest(
            context: selection.context,
            candidate: candidate,
            renderedEmoji: candidate.renderedEmoji,
            trigger: .mouse
        )
        state = .committing(request)
        return [.hidePanel, .commit(request)]
    }

    private mutating func handleTab() -> [AutocompleteEffect] {
        switch state {
        case .candidates(let selection):
            let variants = selection.selectedCandidate.entry.skinToneVariants
            guard variants.count > 1 else {
                state = .idle
                return [.hidePanel, .passThrough(.tab)]
            }
            let currentIndex = variants.firstIndex(of: selection.selectedCandidate.renderedEmoji) ?? 0
            let selectedIndex = SkinToneCycle.nextIndex(after: currentIndex, count: variants.count)
            let toneSelection = SkinToneSelection(
                baseSelection: selection,
                variants: variants,
                selectedIndex: selectedIndex
            )
            state = .skinTones(toneSelection)
            return [.showSkinTones(toneSelection)]
        case .skinTones(let selection):
            let selectedIndex = SkinToneCycle.nextIndex(
                after: selection.selectedIndex,
                count: selection.variants.count
            )
            let updated = SkinToneSelection(
                baseSelection: selection.baseSelection,
                variants: selection.variants,
                selectedIndex: selectedIndex
            )
            state = .skinTones(updated)
            return [.showSkinTones(updated)]
        default:
            return [.passThrough(.tab)]
        }
    }

    private mutating func handleSkinToneSelection(_ selectedIndex: Int) -> [AutocompleteEffect] {
        guard case .skinTones(let selection) = state,
              selection.variants.indices.contains(selectedIndex)
        else {
            return []
        }
        let request = CommitRequest(
            context: selection.baseSelection.context,
            candidate: selection.baseSelection.selectedCandidate,
            renderedEmoji: selection.variants[selectedIndex],
            trigger: .skinTone
        )
        state = .committing(request)
        return [.hidePanel, .commit(request)]
    }

    private mutating func showSkinTones(_ variants: [String]) -> [AutocompleteEffect] {
        guard case .candidates(let selection) = state, variants.isEmpty == false else {
            return []
        }
        let selectedIndex = variants.firstIndex(of: selection.selectedCandidate.renderedEmoji) ?? 0
        let skinToneSelection = SkinToneSelection(
            baseSelection: selection,
            variants: variants,
            selectedIndex: selectedIndex
        )
        state = .skinTones(skinToneSelection)
        return [.showSkinTones(skinToneSelection)]
    }

    private mutating func cancelSkinTones() -> [AutocompleteEffect] {
        guard case .skinTones(let selection) = state else {
            return []
        }
        state = .candidates(selection.baseSelection)
        return [.showCandidates(selection.baseSelection)]
    }

    private func isSuppressed(_ context: AutocompleteTokenContext) -> Bool {
        guard case .dismissed(let dismissedContext) = state else {
            return false
        }
        return dismissedContext.sessionID == context.sessionID
            && dismissedContext.tokenID == context.tokenID
    }
}
