import Foundation

public struct EmojiID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum EmojiCategory: String, CaseIterable, Codable, Sendable {
    case smileysAndEmotion
    case peopleAndBody
    case component
    case animalsAndNature
    case foodAndDrink
    case travelAndPlaces
    case activities
    case objects
    case symbols
    case flags
}

public struct EmojiEntry: Hashable, Codable, Sendable, Identifiable {
    public let id: EmojiID
    public let emoji: String
    public let canonicalName: String
    public let canonicalAlias: String
    public let alternateAliases: [String]
    public let tags: [String]
    public let category: EmojiCategory
    public let sortOrder: Int
    public let skinToneVariants: [String]

    public init(
        id: EmojiID,
        emoji: String,
        canonicalName: String,
        canonicalAlias: String,
        alternateAliases: [String],
        tags: [String],
        category: EmojiCategory,
        sortOrder: Int,
        skinToneVariants: [String]
    ) {
        self.id = id
        self.emoji = emoji
        self.canonicalName = canonicalName
        self.canonicalAlias = canonicalAlias
        self.alternateAliases = alternateAliases
        self.tags = tags
        self.category = category
        self.sortOrder = sortOrder
        self.skinToneVariants = skinToneVariants
    }
}

public enum MatchKind: Int, CaseIterable, Codable, Sendable {
    case exactCanonical
    case exactAlternate
    case canonicalPrefix
    case alternatePrefix
    case tagPrefix
    case aliasContains
    case tagContains
}

public struct EmojiCandidate: Hashable, Codable, Sendable, Identifiable {
    public let id: EmojiID
    public let entry: EmojiEntry
    public let renderedEmoji: String
    public let matchedTerm: String
    public let matchKind: MatchKind
    public let score: Int

    public init(
        id: EmojiID,
        entry: EmojiEntry,
        renderedEmoji: String,
        matchedTerm: String,
        matchKind: MatchKind,
        score: Int
    ) {
        self.id = id
        self.entry = entry
        self.renderedEmoji = renderedEmoji
        self.matchedTerm = matchedTerm
        self.matchKind = matchKind
        self.score = score
    }
}
