import ColonModels
import Foundation
import XCTest
@testable import ColonEmojiData

final class ColonEmojiDataTests: XCTestCase {
    func testBundledFullDatasetLoadsAndBuildsImmutableLookup() throws {
        let snapshot = try EmojiDataStore().load()

        XCTAssertEqual(snapshot.dataset.schemaVersion, 1)
        XCTAssertEqual(snapshot.dataset.metadata.unicodeEmojiVersion, "17.0")
        XCTAssertEqual(snapshot.dataset.metadata.cldrVersion, "48")
        XCTAssertEqual(snapshot.dataset.entries.count, 1_914)
        XCTAssertEqual(snapshot.entriesByID.count, 1_914)
        XCTAssertEqual(snapshot.entriesByID[EmojiID(rawValue: "1f44a")]?.emoji, "👊")
        XCTAssertEqual(snapshot.metrics.entryCount, 1_914)
        XCTAssertGreaterThan(snapshot.metrics.encodedDatasetByteCount, 0)
    }

    func testMissingResourceReturnsTypedFailure() {
        let provider = BundledEmojiDataProvider(
            resourceURL: URL(filePath: "/tmp/colon-does-not-exist.json")
        )

        XCTAssertThrowsError(try provider.loadDataset()) { error in
            XCTAssertEqual(error as? EmojiDataError, .resourceMissing)
        }
    }

    func testMalformedResourceReturnsTypedFailure() throws {
        try withTemporaryFile(data: Data("not-json".utf8)) { url in
            let provider = BundledEmojiDataProvider(resourceURL: url)
            XCTAssertThrowsError(try provider.loadDataset()) { error in
                XCTAssertEqual(error as? EmojiDataError, .malformedResource)
            }
        }
    }

    func testUnsupportedSchemaIsRejected() throws {
        var dataset = makeValidDataset()
        dataset = EmojiDataset(
            schemaVersion: 99,
            metadata: dataset.metadata,
            entries: dataset.entries
        )

        try withDatasetFile(dataset) { url in
            XCTAssertThrowsError(
                try BundledEmojiDataProvider(resourceURL: url).loadDataset()
            ) { error in
                XCTAssertEqual(error as? EmojiDataError, .unsupportedSchema(99))
            }
        }
    }

    func testDuplicateIDsAndInvalidVariantsAreRejected() throws {
        let entry = makeEntry()
        let duplicateDataset = EmojiDataset(
            schemaVersion: 1,
            metadata: makeMetadata(),
            entries: [entry, entry]
        )

        try withDatasetFile(duplicateDataset) { url in
            XCTAssertThrowsError(
                try BundledEmojiDataProvider(resourceURL: url).loadDataset()
            ) { error in
                XCTAssertEqual(error as? EmojiDataError, .duplicateEmojiID("1f44b"))
            }
        }

        let invalidVariantEntry = EmojiEntry(
            id: entry.id,
            emoji: entry.emoji,
            canonicalName: entry.canonicalName,
            canonicalAlias: entry.canonicalAlias,
            alternateAliases: entry.alternateAliases,
            tags: entry.tags,
            category: entry.category,
            sortOrder: entry.sortOrder,
            skinToneVariants: [entry.emoji, "👽"]
        )
        let invalidVariantDataset = EmojiDataset(
            schemaVersion: 1,
            metadata: makeMetadata(),
            entries: [invalidVariantEntry]
        )

        try withDatasetFile(invalidVariantDataset) { url in
            XCTAssertThrowsError(
                try BundledEmojiDataProvider(resourceURL: url).loadDataset()
            ) { error in
                XCTAssertEqual(error as? EmojiDataError, .invalidSkinToneVariant("1f44b"))
            }
        }
    }

    func testStoreLoadsProviderOnlyOnce() throws {
        let provider = CountingProvider(dataset: makeValidDataset())
        let store = EmojiDataStore(provider: provider)

        _ = try store.load()
        _ = try store.load()

        XCTAssertEqual(provider.loadCount, 1)
    }

    func testBundledDatasetLoadMeetsColdTarget() throws {
        let snapshot = try EmojiDataStore().load()
        XCTAssertLessThan(snapshot.metrics.durationNanoseconds, 150_000_000)
    }

    private func makeValidDataset() -> EmojiDataset {
        EmojiDataset(
            schemaVersion: 1,
            metadata: makeMetadata(),
            entries: [makeEntry()]
        )
    }

    private func makeMetadata() -> EmojiDatasetMetadata {
        EmojiDatasetMetadata(
            unicodeEmojiVersion: "17.0",
            cldrVersion: "48",
            gemojiCommit: "test",
            generatedAt: "2026-06-26T00:00:00Z"
        )
    }

    private func makeEntry() -> EmojiEntry {
        EmojiEntry(
            id: EmojiID(rawValue: "1f44b"),
            emoji: "👋",
            canonicalName: "waving hand",
            canonicalAlias: "wave",
            alternateAliases: ["waving_hand"],
            tags: ["hello"],
            category: .peopleAndBody,
            sortOrder: 0,
            skinToneVariants: ["👋", "👋🏻"]
        )
    }

    private func withDatasetFile(
        _ dataset: EmojiDataset,
        operation: (URL) throws -> Void
    ) throws {
        try withTemporaryFile(data: JSONEncoder().encode(dataset), operation: operation)
    }

    private func withTemporaryFile(
        data: Data,
        operation: (URL) throws -> Void
    ) throws {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "ColonEmojiDataTests-\(UUID().uuidString).json",
            directoryHint: .notDirectory
        )
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        try operation(url)
    }
}

private final class CountingProvider: EmojiDataProviding, @unchecked Sendable {
    private let dataset: EmojiDataset
    private let lock = NSLock()
    private var count = 0

    init(dataset: EmojiDataset) {
        self.dataset = dataset
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func loadDataset() throws -> EmojiDataset {
        lock.lock()
        count += 1
        lock.unlock()
        return dataset
    }
}
