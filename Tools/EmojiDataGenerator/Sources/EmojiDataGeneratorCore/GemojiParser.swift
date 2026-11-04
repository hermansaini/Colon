import Foundation

enum GemojiParser {
    static func parse(_ data: Data) throws -> [String: GemojiRecord] {
        let records = try JSONDecoder().decode([GemojiRecord].self, from: data)
        return Dictionary(
            records.map { (EmojiCodePoints.normalizedEmojiKey($0.emoji), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

enum AliasOverridesParser {
    static func parse(_ data: Data) throws -> AliasOverridesFile {
        let overrides = try JSONDecoder().decode(AliasOverridesFile.self, from: data)
        guard overrides.schemaVersion == 1 else {
            throw EmojiDataGeneratorError.invalidOverridesSchema(overrides.schemaVersion)
        }
        return overrides
    }
}
