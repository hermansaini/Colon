import ColonEmojiData
import ColonModels
import Foundation
import XCTest
@testable import ColonSearch

final class EmojiSearchEngineTests: XCTestCase {
    func testExactCanonicalBeatsExactAlternateAndPrefixes() {
        let engine = makeEngine(entries: [
            entry(id: "a", alias: "fist", order: 2),
            entry(id: "b", alias: "closed_hand", aliases: ["fist"], order: 0),
            entry(id: "c", alias: "fist_bump", order: 1),
        ])

        let results = engine.search(query: "fist", maximumResultCount: 10)

        XCTAssertEqual(results.map(\.id.rawValue), ["a", "b", "c"])
        XCTAssertEqual(results.map(\.matchKind), [.exactCanonical, .exactAlternate, .canonicalPrefix])
    }

    func testExactAlternateBeatsAllPrefixClasses() {
        let engine = makeEngine(entries: [
            entry(id: "alternate", alias: "closed_hand", aliases: ["punch"], order: 3),
            entry(id: "canonical-prefix", alias: "punching", order: 0),
            entry(id: "alternate-prefix", alias: "other", aliases: ["punchy"], order: 1),
            entry(id: "tag-prefix", alias: "tagged", tags: ["punchline"], order: 2),
        ])

        XCTAssertEqual(
            engine.search(query: "punch", maximumResultCount: 10).map(\.id.rawValue),
            ["alternate", "canonical-prefix", "alternate-prefix", "tag-prefix"]
        )
    }

    func testCanonicalPrefixBeatsAlternateAndTagPrefixes() {
        let engine = makeEngine(entries: [
            entry(id: "tag", alias: "one", tags: ["handy"], order: 0),
            entry(id: "alternate", alias: "two", aliases: ["handle"], order: 1),
            entry(id: "canonical", alias: "handshake", order: 2),
        ])

        XCTAssertEqual(
            engine.search(query: "hand", maximumResultCount: 10).map(\.id.rawValue),
            ["canonical", "alternate", "tag"]
        )
    }

    func testContainsResultsFollowEveryPrefixClass() {
        let engine = makeEngine(entries: [
            entry(id: "tag-contains", alias: "one", tags: ["two_hands"], order: 0),
            entry(id: "alias-contains", alias: "left_hand", order: 1),
            entry(id: "tag-prefix", alias: "three", tags: ["handy"], order: 2),
            entry(id: "canonical-prefix", alias: "handshake", order: 3),
        ])

        let results = engine.search(query: "hand", maximumResultCount: 10)

        XCTAssertEqual(results.map(\.id.rawValue), ["canonical-prefix", "tag-prefix", "alias-contains", "tag-contains"])
        XCTAssertEqual(results.map(\.matchKind), [.canonicalPrefix, .tagPrefix, .aliasContains, .tagContains])
    }

    func testResultLimitIsFilledBeforeLowerRankedContainsMatches() {
        let engine = makeEngine(entries: [
            entry(id: "prefix", alias: "handshake", order: 0),
            entry(id: "contains", alias: "right_hand", order: 1),
        ])

        let results = engine.search(query: "hand", maximumResultCount: 1)

        XCTAssertEqual(results.map(\.id.rawValue), ["prefix"])
        XCTAssertEqual(results.first?.matchKind, .canonicalPrefix)
    }

    func testMisspellingsDoNotProduceFuzzyResults() {
        let engine = makeEngine(entries: [entry(id: "fist", alias: "fist", order: 0)])

        XCTAssertTrue(engine.search(query: "fsit", maximumResultCount: 10).isEmpty)
    }

    func testDuplicateMatchesReturnBestSingleCandidateAndHint() {
        let engine = makeEngine(entries: [
            entry(
                id: "fist",
                alias: "oncoming_fist",
                aliases: ["fist", "punch"],
                tags: ["punch", "hand"],
                order: 0
            ),
        ])

        let results = engine.search(query: "punch", maximumResultCount: 10)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].matchedTerm, "punch")
        XCTAssertEqual(results[0].matchKind, .exactAlternate)
    }

    func testCustomExactAndPrefixTagsUseTagPrefixLevel() {
        let taggedEntry = entry(id: "wave", alias: "waving_hand", order: 0)
        let canonicalEntry = entry(id: "canonical", alias: "celebration", order: 1)
        let customTags = CustomTagsSnapshot(
            schemaVersion: CustomTagsSnapshot.currentSchemaVersion,
            records: [
                CustomTagRecord(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    emojiID: taggedEntry.id,
                    normalizedTag: "celebrate",
                    createdAt: .distantPast,
                    updatedAt: .distantPast
                ),
            ]
        )
        let engine = makeEngine(entries: [taggedEntry, canonicalEntry], customTags: customTags)

        let exact = engine.search(query: "celebrate", maximumResultCount: 10)
        XCTAssertEqual(exact.first?.id, taggedEntry.id)
        XCTAssertEqual(exact.first?.matchedTerm, "celebrate")
        XCTAssertEqual(exact.first?.matchKind, .tagPrefix)

        let prefix = engine.search(query: "cele", maximumResultCount: 10)
        XCTAssertEqual(prefix.map(\.id.rawValue), ["canonical", "wave"])
        XCTAssertEqual(prefix.last?.matchKind, .tagPrefix)
    }

    func testResultLimitAndOrderAreStableAcrossRuns() {
        let engine = makeEngine(entries: (0..<20).map {
            entry(id: "id-\($0)", alias: "hand_\($0)", order: $0)
        })
        let expected = engine.search(query: "hand", maximumResultCount: 7)

        XCTAssertEqual(expected.count, 7)
        for _ in 0..<50 {
            XCTAssertEqual(engine.search(query: "hand", maximumResultCount: 7), expected)
        }
    }

    func testPreferredSkinToneRendersWithoutChangingBaseIdentity() {
        let base = entry(
            id: "wave",
            alias: "wave",
            emoji: "👋",
            variants: ["👋", "👋🏽"],
            order: 0
        )
        let preferences = SkinTonePreferencesSnapshot(
            schemaVersion: SkinTonePreferencesSnapshot.currentSchemaVersion,
            preferences: [
                SkinTonePreference(emojiID: base.id, selectedVariant: "👋🏽", updatedAt: .now),
            ]
        )
        let engine = makeEngine(entries: [base], skinTones: preferences)

        let result = engine.search(query: "wave", maximumResultCount: 1).first

        XCTAssertEqual(result?.id, base.id)
        XCTAssertEqual(result?.entry.emoji, "👋")
        XCTAssertEqual(result?.renderedEmoji, "👋🏽")
    }

    func testWarmQueriesMeetLatencyTarget() throws {
        let dataset = try EmojiDataStore().load().dataset
        let engineBuildStartedAt = DispatchTime.now().uptimeNanoseconds
        let engine = EmojiSearchEngine(dataset: dataset)
        let engineBuildMilliseconds = Double(
            DispatchTime.now().uptimeNanoseconds - engineBuildStartedAt
        ) / 1_000_000
        let queries = ["h", "s", "fist", "punch", "hand", "thumbsup", "thumbs_up", "nd", "qz"]
        for query in queries {
            _ = engine.search(query: query, maximumResultCount: 50)
        }

        let start = DispatchTime.now().uptimeNanoseconds
        var queryDurations: [UInt64] = []
        for _ in 0..<20 {
            for query in queries {
                let queryStartedAt = DispatchTime.now().uptimeNanoseconds
                _ = engine.search(query: query, maximumResultCount: 50)
                queryDurations.append(DispatchTime.now().uptimeNanoseconds - queryStartedAt)
            }
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        let averageMilliseconds = Double(elapsed) / Double(queryDurations.count) / 1_000_000
        let sortedDurations = queryDurations.sorted()
        let p95Milliseconds = Double(
            sortedDurations[(sortedDurations.count - 1) * 95 / 100]
        ) / 1_000_000

        print(String(
            format: "Warm search: build %.2f ms, average %.2f ms, p95 %.2f ms",
            engineBuildMilliseconds,
            averageMilliseconds,
            p95Milliseconds
        ))
        XCTAssertLessThan(averageMilliseconds, 20)
        XCTAssertLessThan(p95Milliseconds, 5)
    }

    private func makeEngine(
        entries: [EmojiEntry],
        customTags: CustomTagsSnapshot = .defaults,
        skinTones: SkinTonePreferencesSnapshot = .defaults
    ) -> EmojiSearchEngine {
        EmojiSearchEngine(
            dataset: EmojiDataset(
                schemaVersion: EmojiDataset.currentSchemaVersion,
                metadata: EmojiDatasetMetadata(
                    unicodeEmojiVersion: "test",
                    cldrVersion: "test",
                    gemojiCommit: "test",
                    generatedAt: "test"
                ),
                entries: entries
            ),
            customTags: customTags,
            skinTonePreferences: skinTones
        )
    }

    private func entry(
        id: String,
        alias: String,
        aliases: [String] = [],
        tags: [String] = [],
        emoji: String = "🙂",
        variants: [String] = ["🙂"],
        order: Int
    ) -> EmojiEntry {
        EmojiEntry(
            id: EmojiID(rawValue: id),
            emoji: emoji,
            canonicalName: alias.replacingOccurrences(of: "_", with: " "),
            canonicalAlias: alias,
            alternateAliases: aliases,
            tags: tags,
            category: .peopleAndBody,
            sortOrder: order,
            skinToneVariants: variants
        )
    }
}
