import Foundation

struct UnicodeEmojiRecord: Sendable, Equatable {
    let codePoints: [UInt32]
    let emoji: String
    let name: String
    let category: String
    let sourceOrder: Int
}

struct UnicodeEmojiTestData: Sendable {
    let version: String
    let records: [UnicodeEmojiRecord]
}

struct CLDRAnnotation: Sendable, Equatable {
    var name: String?
    var tags: [String]
}

struct GemojiRecord: Decodable, Sendable {
    let emoji: String
    let description: String
    let category: String
    let aliases: [String]
    let tags: [String]
    let skinTones: Bool?

    private enum CodingKeys: String, CodingKey {
        case emoji
        case description
        case category
        case aliases
        case tags
        case skinTones = "skin_tones"
    }
}

struct AliasOverridesFile: Decodable, Sendable {
    let schemaVersion: Int
    let entries: [String: AliasOverride]
}

struct AliasOverride: Decodable, Sendable {
    let canonicalAlias: String?
    let alternateAliases: [String]
    let excludedAliases: [String]
    let tags: [String]
}
