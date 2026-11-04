import Foundation

public protocol TextCommitClient: MinimalTextClient {
    func replaceText(with text: String, replacementRange: NSRange)
}

public struct TextCommitExpectation: Equatable, Sendable {
    public let normalizedQuery: String
    public let documentRange: NSRange
    public let replacementText: String

    public init(
        normalizedQuery: String,
        documentRange: NSRange,
        replacementText: String
    ) {
        self.normalizedQuery = normalizedQuery
        self.documentRange = documentRange
        self.replacementText = replacementText
    }
}

public enum TextCommitRejection: String, Equatable, Sendable {
    case invalidReplacementText
    case contextUnavailable
    case tokenMismatch
    case rangeMismatch
}

public enum TextCommitOutcome: Equatable, Sendable {
    case committed(replacementRange: NSRange)
    case rejected(TextCommitRejection)

    public var didCommit: Bool {
        if case .committed = self {
            return true
        }
        return false
    }
}

public struct TextCommitter: Sendable {
    private let contextReader: MinimalTextContextReader
    private let tokenDetector: EmojiTokenDetector

    public init(maximumContextUTF16Length: Int = 256) {
        contextReader = MinimalTextContextReader(
            maximumUTF16Length: maximumContextUTF16Length
        )
        tokenDetector = EmojiTokenDetector()
    }

    public func commit(
        _ expectation: TextCommitExpectation,
        to client: any TextCommitClient
    ) -> TextCommitOutcome {
        guard expectation.replacementText.isEmpty == false else {
            return .rejected(.invalidReplacementText)
        }
        guard client.selectedRange.length == 0,
              let context = contextReader.read(from: client)
        else {
            return .rejected(.contextUnavailable)
        }

        let detection = tokenDetector.detect(in: context.snapshot)
        guard detection.state == .activeQuery || detection.state == .closingColonIntent,
              detection.normalizedQuery == expectation.normalizedQuery,
              let localRange = detection.replacementRange,
              context.hasKnownTokenStart(at: localRange.location)
        else {
            return .rejected(.tokenMismatch)
        }
        guard context.documentRange(for: localRange) == expectation.documentRange else {
            return .rejected(.rangeMismatch)
        }

        client.replaceText(
            with: expectation.replacementText,
            replacementRange: expectation.documentRange
        )
        return .committed(replacementRange: expectation.documentRange)
    }
}
