import Foundation

public struct TextContextSnapshot: Equatable, Sendable {
    public let textBeforeCaret: String

    public init(textBeforeCaret: String) {
        self.textBeforeCaret = textBeforeCaret
    }
}

public enum EmojiTokenState: String, Equatable, Sendable {
    case inactive
    case colonOnly
    case activeQuery
    case closingColonIntent
    case terminatedOrInvalid
}

public struct EmojiTokenDetection: Equatable, Sendable {
    public let state: EmojiTokenState
    public let replacementRange: NSRange?
    public let rawQuery: String?
    public let normalizedQuery: String?

    public var hasClosingColonIntent: Bool {
        state == .closingColonIntent
    }

    public static let inactive = EmojiTokenDetection(
        state: .inactive,
        replacementRange: nil,
        rawQuery: nil,
        normalizedQuery: nil
    )

    public init(
        state: EmojiTokenState,
        replacementRange: NSRange?,
        rawQuery: String?,
        normalizedQuery: String?
    ) {
        self.state = state
        self.replacementRange = replacementRange
        self.rawQuery = rawQuery
        self.normalizedQuery = normalizedQuery
    }
}

public struct EmojiTokenDetector: Sendable {
    public init() {}

    public func detect(in snapshot: TextContextSnapshot) -> EmojiTokenDetection {
        let text = snapshot.textBeforeCaret
        let segmentStart = text.lastIndex(where: \Character.isWhitespace).map {
            text.index(after: $0)
        } ?? text.startIndex
        let segmentRange = segmentStart..<text.endIndex
        let segment = text[segmentRange]

        guard segment.first == ":" else {
            return .inactive
        }

        let replacementRange = NSRange(segmentRange, in: text)
        let body = segment.dropFirst()

        guard body.isEmpty == false else {
            return EmojiTokenDetection(
                state: .colonOnly,
                replacementRange: replacementRange,
                rawQuery: "",
                normalizedQuery: ""
            )
        }

        if body.last == ":" {
            let rawQuery = String(body.dropLast())
            guard rawQuery.isEmpty == false,
                  let normalizedQuery = EmojiQueryNormalizer.normalize(rawQuery)
            else {
                return invalidDetection(range: replacementRange)
            }

            return EmojiTokenDetection(
                state: .closingColonIntent,
                replacementRange: replacementRange,
                rawQuery: rawQuery,
                normalizedQuery: normalizedQuery
            )
        }

        let rawQuery = String(body)
        guard let normalizedQuery = EmojiQueryNormalizer.normalize(rawQuery) else {
            return invalidDetection(range: replacementRange)
        }

        return EmojiTokenDetection(
            state: .activeQuery,
            replacementRange: replacementRange,
            rawQuery: rawQuery,
            normalizedQuery: normalizedQuery
        )
    }

    private func invalidDetection(range: NSRange) -> EmojiTokenDetection {
        EmojiTokenDetection(
            state: .terminatedOrInvalid,
            replacementRange: range,
            rawQuery: nil,
            normalizedQuery: nil
        )
    }
}
