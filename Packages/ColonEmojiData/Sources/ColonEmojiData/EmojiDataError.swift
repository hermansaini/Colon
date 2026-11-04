public enum EmojiDataError: Error, Equatable, Sendable {
    case resourceMissing
    case unreadableResource
    case malformedResource
    case unsupportedSchema(Int)
    case emptyDataset
    case duplicateEmojiID(String)
    case duplicateAlias(String)
    case invalidEntry(String)
    case invalidSkinToneVariant(String)
}
