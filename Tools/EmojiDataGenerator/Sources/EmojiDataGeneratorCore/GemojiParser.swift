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

/// Slack documents iamcal/emoji-data as its standard emoji shortcode source.
/// Match Unicode scalars rather than names; ignore presentation selectors.
enum SlackEmojiDataParser {
    private struct Record: Decodable {
        let unified: String
        let short_names: [String]
    }

    static func parse(_ data: Data) throws -> [String: [String]] {
        var result: [String: [String]] = [:]
        for record in try JSONDecoder().decode([Record].self, from: data) {
            let points = try record.unified.split(separator: "-").map { component in
                guard let value = UInt32(component, radix: 16), Unicode.Scalar(value) != nil else {
                    throw EmojiDataGeneratorError.invalidEntry(record.unified)
                }
                return value
            }
            let id = EmojiCodePoints.stableID(points)
            result[id] = stableUnique((result[id] ?? []) + record.short_names.map(EmojiTermNormalizer.normalize))
                .filter { !$0.isEmpty }
        }
        return result
    }
}
