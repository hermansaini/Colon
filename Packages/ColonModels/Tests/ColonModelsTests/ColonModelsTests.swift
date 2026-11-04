import XCTest
@testable import ColonModels

final class ColonModelsTests: XCTestCase {
    func testEmojiModelsRoundTrip() throws {
        let emojiID = EmojiID(rawValue: "1F44B")
        let entry = EmojiEntry(
            id: emojiID,
            emoji: "👋",
            canonicalName: "waving hand",
            canonicalAlias: "wave",
            alternateAliases: ["waving_hand"],
            tags: ["hello", "goodbye"],
            category: .peopleAndBody,
            sortOrder: 42,
            skinToneVariants: ["👋", "👋🏻", "👋🏿"]
        )
        let candidate = EmojiCandidate(
            id: emojiID,
            entry: entry,
            renderedEmoji: "👋🏿",
            matchedTerm: "wave",
            matchKind: .exactCanonical,
            score: 10_000
        )

        try assertRoundTrip(emojiID)
        try assertRoundTrip(entry)
        try assertRoundTrip(candidate)
        try assertRoundTrip(
            EmojiDataset(
                schemaVersion: EmojiDataset.currentSchemaVersion,
                metadata: EmojiDatasetMetadata(
                    unicodeEmojiVersion: "17.0",
                    cldrVersion: "48",
                    gemojiCommit: "abc123",
                    generatedAt: "2026-06-26T00:00:00Z"
                ),
                entries: [entry]
            )
        )

        for category in EmojiCategory.allCases {
            try assertRoundTrip(category)
        }
        for matchKind in MatchKind.allCases {
            try assertRoundTrip(matchKind)
        }
    }

    func testSettingsModelsRoundTrip() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let emojiID = EmojiID(rawValue: "1F44B")
        let customTag = CustomTagRecord(
            id: UUID(uuidString: "A25E8F0A-E515-4A6D-B986-1D19C7A47FD4")!,
            emojiID: emojiID,
            normalizedTag: "greeting",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let tonePreference = SkinTonePreference(
            emojiID: emojiID,
            selectedVariant: "👋🏿",
            updatedAt: timestamp
        )

        try assertRoundTrip(ColonSettingsSnapshot.defaults)
        try assertRoundTrip(
            CustomTagsSnapshot(
                schemaVersion: CustomTagsSnapshot.currentSchemaVersion,
                records: [customTag]
            )
        )
        try assertRoundTrip(
            SkinTonePreferencesSnapshot(
                schemaVersion: SkinTonePreferencesSnapshot.currentSchemaVersion,
                preferences: [tonePreference]
            )
        )
    }

    func testDefaultSettingsExactlyMatchApprovedDefaults() {
        let settings = ColonSettingsSnapshot.defaults

        XCTAssertEqual(settings.schemaVersion, 1)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.launchAtLoginPreferred)
        XCTAssertTrue(settings.menuBarVisible)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.pickerSize, .standard)
        XCTAssertEqual(settings.visibleRowCount, 6)
        XCTAssertEqual(settings.maximumResultCount, 50)
        XCTAssertEqual(settings.enabledApps.count, 8)
        XCTAssertEqual(
            settings.enabledApps,
            Dictionary(uniqueKeysWithValues: SupportedApplication.allCases.map { ($0.rawValue, true) })
        )
    }

    func testSupportedApplicationIdentifiersAreStable() {
        XCTAssertEqual(SupportedApplication.messages.rawValue, "com.apple.MobileSMS")
        XCTAssertEqual(SupportedApplication.notes.rawValue, "com.apple.Notes")
        XCTAssertEqual(SupportedApplication.mail.rawValue, "com.apple.mail")
        XCTAssertEqual(SupportedApplication.safari.rawValue, "com.apple.Safari")
        XCTAssertEqual(SupportedApplication.chrome.rawValue, "com.google.Chrome")
        XCTAssertEqual(SupportedApplication.slack.rawValue, "com.tinyspeck.slackmacgap")
        XCTAssertEqual(SupportedApplication.discord.rawValue, "com.hnc.Discord")
        XCTAssertEqual(SupportedApplication.notion.rawValue, "notion.id")
    }

    func testDiagnosticModelsRoundTrip() throws {
        let event = DiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            subsystem: .settings,
            code: .settingsCorruptRecovered,
            metadata: DiagnosticMetadata(
                clientApplication: .messages,
                operatingSystemVersion: DiagnosticVersion(major: 26, minor: 0, patch: 0),
                appVersion: DiagnosticVersion(major: 0, minor: 1, patch: 0, build: 1),
                status: .recovered,
                errorDomain: .settings,
                numericErrorCode: 1,
                architecture: .arm64
            )
        )

        try assertRoundTrip(event)
    }

    func testDiagnosticMetadataRejectsNonAllowlistedTypedTextField() {
        let data = Data(
            """
            {
              "clientApplication": "com.apple.MobileSMS",
              "typedText": "private message"
            }
            """.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(DiagnosticMetadata.self, from: data))
    }

    private func assertRoundTrip<Value>(_ value: Value) throws
    where Value: Codable & Equatable {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }
}
