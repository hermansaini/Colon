public struct EmojiDatasetMetadata: Codable, Sendable, Equatable {
    public let unicodeEmojiVersion: String
    public let cldrVersion: String
    public let gemojiCommit: String
    public let generatedAt: String

    public init(
        unicodeEmojiVersion: String,
        cldrVersion: String,
        gemojiCommit: String,
        generatedAt: String
    ) {
        self.unicodeEmojiVersion = unicodeEmojiVersion
        self.cldrVersion = cldrVersion
        self.gemojiCommit = gemojiCommit
        self.generatedAt = generatedAt
    }
}

public struct EmojiDataset: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let metadata: EmojiDatasetMetadata
    public let entries: [EmojiEntry]

    public init(
        schemaVersion: Int,
        metadata: EmojiDatasetMetadata,
        entries: [EmojiEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.metadata = metadata
        self.entries = entries
    }
}
