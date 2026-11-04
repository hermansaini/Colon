import Foundation

public enum EmojiDataGeneratorError: Error, CustomStringConvertible, Equatable {
    case missingConfiguredSource(EmojiDataSourceKind)
    case checksumMismatch(kind: EmojiDataSourceKind, expected: String, actual: String)
    case unicodeVersionMismatch(expected: String, actual: String)
    case malformedUnicodeLine(Int)
    case unsupportedUnicodeCategory(String)
    case xmlParseFailed(String)
    case invalidOverridesSchema(Int)
    case duplicateEmojiID(String)
    case duplicateAlias(alias: String, firstID: String, secondID: String)
    case invalidEntry(String)
    case unofficialSkinToneVariant(emojiID: String, variant: String)
    case unknownOverride(String)
    case generatedFileMissing(String)
    case generatedFileOutOfDate(String)

    public var description: String {
        switch self {
        case let .missingConfiguredSource(kind):
            "Missing configured source: \(kind.rawValue)"
        case let .checksumMismatch(kind, expected, actual):
            "Checksum mismatch for \(kind.rawValue): expected \(expected), found \(actual)"
        case let .unicodeVersionMismatch(expected, actual):
            "Unicode Emoji version mismatch: expected \(expected), found \(actual)"
        case let .malformedUnicodeLine(line):
            "Malformed Unicode data at line \(line)"
        case let .unsupportedUnicodeCategory(category):
            "Unsupported Unicode emoji category: \(category)"
        case let .xmlParseFailed(message):
            "CLDR XML parse failed: \(message)"
        case let .invalidOverridesSchema(schema):
            "Unsupported alias override schema: \(schema)"
        case let .duplicateEmojiID(id):
            "Duplicate emoji ID: \(id)"
        case let .duplicateAlias(alias, firstID, secondID):
            "Duplicate alias \(alias) belongs to both \(firstID) and \(secondID)"
        case let .invalidEntry(id):
            "Invalid generated emoji entry: \(id)"
        case let .unofficialSkinToneVariant(emojiID, variant):
            "Emoji \(emojiID) contains an unofficial skin-tone variant: \(variant)"
        case let .unknownOverride(id):
            "Alias override references an unknown emoji ID: \(id)"
        case let .generatedFileMissing(path):
            "Generated file is missing: \(path)"
        case let .generatedFileOutOfDate(path):
            "Generated file is out of date: \(path)"
        }
    }
}
