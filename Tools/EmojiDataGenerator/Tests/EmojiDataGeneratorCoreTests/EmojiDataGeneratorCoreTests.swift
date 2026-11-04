import ColonModels
import Foundation
import XCTest
@testable import EmojiDataGeneratorCore

final class EmojiDataGeneratorCoreTests: XCTestCase {
    func testNormalizerPreservesApprovedQueryCharacters() {
        XCTAssertEqual(EmojiTermNormalizer.normalize("  C++ thumbs up  "), "c++_thumbs_up")
        XCTAssertEqual(EmojiTermNormalizer.normalize("flag: United States"), "flag_united_states")
    }

    func testRepresentativeEntriesMatchGoldenFixture() throws {
        let artifacts = try makeGenerator().generate()
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(forResource: "golden-representative", withExtension: "json")
        )
        let expected = try JSONDecoder().decode(
            [GoldenEntry].self,
            from: Data(contentsOf: fixtureURL)
        )
        let entriesByID = Dictionary(
            uniqueKeysWithValues: artifacts.dataset.entries.map { ($0.id.rawValue, $0) }
        )
        let actual = try expected.map { golden in
            let entry = try XCTUnwrap(entriesByID[golden.id])
            return GoldenEntry(entry: entry)
        }

        XCTAssertEqual(actual, expected)
    }

    func testTwoGenerationRunsAreByteIdentical() throws {
        let generator = makeGenerator()
        let first = try generator.generate()
        let second = try generator.generate()

        XCTAssertEqual(first.datasetData, second.datasetData)
        XCTAssertEqual(first.provenanceData, second.provenanceData)
        XCTAssertEqual(first.noticesData, second.noticesData)
    }

    func testCompatibilityAliasesMapToExpectedEmoji() throws {
        let dataset = try makeGenerator().generate().dataset
        let aliasesByID = Dictionary(
            uniqueKeysWithValues: dataset.entries.map {
                ($0.id.rawValue, Set([$0.canonicalAlias] + $0.alternateAliases))
            }
        )

        XCTAssertTrue(try XCTUnwrap(aliasesByID["1f44d"]).contains("thumbsup"))
        XCTAssertTrue(try XCTUnwrap(aliasesByID["1f44d"]).contains("thumbs_up"))
        XCTAssertTrue(try XCTUnwrap(aliasesByID["1f44a"]).contains("punch"))
        XCTAssertTrue(try XCTUnwrap(aliasesByID["1f44a"]).contains("facepunch"))
    }

    func testEveryStoredSkinToneVariantIsAnOfficialSequence() throws {
        let generator = makeGenerator()
        let dataset = try generator.generate().dataset
        let configuration = generator.configuration
        let sequenceSource = try configuration.source(for: .unicodeEmojiSequences)
        let zwjSource = try configuration.source(for: .unicodeEmojiZWJSequences)
        let officialSequences = try UnicodeEmojiSequenceParser.officialSkinToneSequenceKeys(
            from: [
                Data(contentsOf: configuration.url(for: sequenceSource)),
                Data(contentsOf: configuration.url(for: zwjSource)),
            ]
        )

        for entry in dataset.entries {
            for variant in entry.skinToneVariants.dropFirst() {
                XCTAssertTrue(
                    officialSequences.contains(
                        EmojiCodePoints.codePointKey(EmojiCodePoints.values(in: variant))
                    ),
                    "Unofficial variant \(variant) for \(entry.id.rawValue)"
                )
            }
        }
    }

    func testValidatorRejectsDuplicateIDsAndAliases() throws {
        let metadata = EmojiDatasetMetadata(
            unicodeEmojiVersion: "17.0",
            cldrVersion: "48",
            gemojiCommit: "test",
            generatedAt: "2026-06-26T00:00:00Z"
        )
        let first = makeEntry(id: "1f600", emoji: "😀", alias: "happy", sortOrder: 0)
        let duplicateID = makeEntry(id: "1f600", emoji: "😀", alias: "other", sortOrder: 1)
        let duplicateAlias = makeEntry(id: "1f603", emoji: "😃", alias: "happy", sortOrder: 1)

        XCTAssertThrowsError(
            try EmojiDatasetValidator.validate(
                EmojiDataset(schemaVersion: 1, metadata: metadata, entries: [first, duplicateID]),
                officialSkinToneSequenceKeys: []
            )
        ) { error in
            XCTAssertEqual(error as? EmojiDataGeneratorError, .duplicateEmojiID("1f600"))
        }

        XCTAssertThrowsError(
            try EmojiDatasetValidator.validate(
                EmojiDataset(schemaVersion: 1, metadata: metadata, entries: [first, duplicateAlias]),
                officialSkinToneSequenceKeys: []
            )
        ) { error in
            XCTAssertEqual(
                error as? EmojiDataGeneratorError,
                .duplicateAlias(alias: "happy", firstID: "1f600", secondID: "1f603")
            )
        }
    }

    private func makeGenerator() -> EmojiDataGenerator {
        EmojiDataGenerator(
            configuration: .standard(repositoryRootURL: repositoryRootURL)
        )
    }

    private var repositoryRootURL: URL {
        var url = URL(filePath: #filePath, directoryHint: .notDirectory)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private func makeEntry(
        id: String,
        emoji: String,
        alias: String,
        sortOrder: Int
    ) -> EmojiEntry {
        EmojiEntry(
            id: EmojiID(rawValue: id),
            emoji: emoji,
            canonicalName: alias,
            canonicalAlias: alias,
            alternateAliases: [],
            tags: [],
            category: .smileysAndEmotion,
            sortOrder: sortOrder,
            skinToneVariants: [emoji]
        )
    }
}

private struct GoldenEntry: Codable, Equatable {
    let id: String
    let emoji: String
    let canonicalName: String
    let canonicalAlias: String
    let alternateAliases: [String]
    let category: EmojiCategory
    let skinToneVariantCount: Int

    init(entry: EmojiEntry) {
        id = entry.id.rawValue
        emoji = entry.emoji
        canonicalName = entry.canonicalName
        canonicalAlias = entry.canonicalAlias
        alternateAliases = entry.alternateAliases
        category = entry.category
        skinToneVariantCount = entry.skinToneVariants.count
    }
}
