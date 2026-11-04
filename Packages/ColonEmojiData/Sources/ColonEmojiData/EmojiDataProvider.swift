import ColonModels
import Foundation

public protocol EmojiDataProviding: Sendable {
    func loadDataset() throws -> EmojiDataset
}

public struct BundledEmojiDataProvider: EmojiDataProviding, Sendable {
    private let resourceURL: URL?

    public init(resourceURL: URL?) {
        self.resourceURL = resourceURL
    }

    public static func bundled() -> Self {
        Self(
            resourceURL: Bundle.module.url(
                forResource: "emoji-index",
                withExtension: "json"
            )
        )
    }

    public func loadDataset() throws -> EmojiDataset {
        guard let resourceURL,
              FileManager.default.fileExists(atPath: resourceURL.path)
        else {
            throw EmojiDataError.resourceMissing
        }

        let data: Data
        do {
            data = try Data(contentsOf: resourceURL)
        } catch {
            throw EmojiDataError.unreadableResource
        }

        let dataset: EmojiDataset
        do {
            dataset = try JSONDecoder().decode(EmojiDataset.self, from: data)
        } catch {
            throw EmojiDataError.malformedResource
        }

        try EmojiDatasetRuntimeValidator.validate(dataset)
        return dataset
    }
}
