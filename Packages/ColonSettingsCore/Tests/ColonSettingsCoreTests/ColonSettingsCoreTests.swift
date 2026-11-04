import ColonModels
import Foundation
import XCTest
@testable import ColonSettingsCore

final class ColonSettingsCoreTests: XCTestCase {
    func testStoragePathsUseVersionedFiles() {
        let rootURL = URL(filePath: "/tmp/colon-test", directoryHint: .isDirectory)
        let paths = ColonStoragePaths(rootDirectoryURL: rootURL)

        XCTAssertEqual(paths.settingsURL.lastPathComponent, "settings-v1.json")
        XCTAssertEqual(paths.customTagsURL.lastPathComponent, "custom-tags-v1.json")
        XCTAssertEqual(paths.skinTonePreferencesURL.lastPathComponent, "skin-tones-v1.json")
        XCTAssertEqual(paths.diagnosticsDirectoryURL.lastPathComponent, "diagnostics")
    }

    func testMissingFilesLoadSafeDefaults() throws {
        try withTemporaryStore { store, _ in
            XCTAssertEqual(try store.currentSnapshot(), .defaults)
            XCTAssertEqual(try store.currentCustomTags(), .defaults)
            XCTAssertEqual(try store.currentSkinTonePreferences(), .defaults)
        }
    }

    func testAtomicSettingsWriteCanBeReadByNewStore() throws {
        try withTemporaryStore { store, paths in
            try store.update { snapshot in
                snapshot.isEnabled = false
                snapshot.appearance = .dark
            }

            let secondStore = try ColonLocalStore(paths: paths)
            let snapshot = try secondStore.currentSnapshot()
            XCTAssertFalse(snapshot.isEnabled)
            XCTAssertEqual(snapshot.appearance, .dark)

            let data = try Data(contentsOf: paths.settingsURL)
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
        }
    }

    func testCorruptFileIsBackedUpAndReplacedWithSafeDefaults() throws {
        let recoveryDate = Date(timeIntervalSince1970: 1_700_000_000)

        try withTemporaryStore(now: { recoveryDate }) { store, paths in
            try Data("not-json".utf8).write(to: paths.settingsURL)

            XCTAssertEqual(try store.currentSnapshot(), .defaults)

            let notices = store.storageRecoveryNotices()
            XCTAssertEqual(notices.count, 1)
            XCTAssertEqual(notices.first?.document, .settings)
            XCTAssertEqual(notices.first?.recoveredAt, recoveryDate)

            let backupURL = try XCTUnwrap(notices.first?.backupURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
            XCTAssertEqual(try Data(contentsOf: backupURL), Data("not-json".utf8))

            let recoveredStore = try ColonLocalStore(paths: paths)
            XCTAssertEqual(try recoveredStore.currentSnapshot(), .defaults)
        }
    }

    func testUnsupportedSchemaIsBackedUpAndRecoversToCurrentDefaults() throws {
        try withTemporaryStore { store, paths in
            var futureSnapshot = ColonSettingsSnapshot.defaults
            futureSnapshot.schemaVersion = 99
            try JSONEncoder().encode(futureSnapshot).write(to: paths.settingsURL)

            XCTAssertEqual(try store.currentSnapshot(), .defaults)
            XCTAssertEqual(store.storageRecoveryNotices().count, 1)
            XCTAssertNotNil(store.storageRecoveryNotices().first?.backupURL)
        }
    }

    func testCustomTagsAndSkinTonesPersistInSeparateVersionedFiles() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let emojiID = EmojiID(rawValue: "1F44B")
        let tag = CustomTagRecord(
            id: UUID(uuidString: "A25E8F0A-E515-4A6D-B986-1D19C7A47FD4")!,
            emojiID: emojiID,
            normalizedTag: "greeting",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let preference = SkinTonePreference(
            emojiID: emojiID,
            selectedVariant: "👋🏿",
            updatedAt: timestamp
        )

        try withTemporaryStore { store, _ in
            try store.updateCustomTags { $0.records = [tag] }
            try store.updateSkinTonePreferences { $0.preferences = [preference] }

            XCTAssertEqual(try store.currentCustomTags().records, [tag])
            XCTAssertEqual(try store.currentSkinTonePreferences().preferences, [preference])
        }
    }

    func testCustomTagAddNormalizesDeduplicatesAndRemoves() throws {
        let emojiID = EmojiID(rawValue: "wave")
        let recordID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let timestamp = Date(timeIntervalSince1970: 100)

        try withTemporaryStore { store, _ in
            let record = try store.addCustomTag(
                emojiID: emojiID,
                tag: "  Greeting_2+  ",
                recordID: recordID,
                timestamp: timestamp
            )
            XCTAssertEqual(record.normalizedTag, "greeting_2+")
            XCTAssertEqual(try store.currentCustomTags().records, [record])

            XCTAssertThrowsError(
                try store.addCustomTag(
                    emojiID: emojiID,
                    tag: "GREETING_2+",
                    recordID: UUID(),
                    timestamp: timestamp
                )
            ) { error in
                XCTAssertEqual(error as? CustomTagMutationError, .duplicate)
            }

            try store.removeCustomTag(id: record.id)
            XCTAssertEqual(try store.currentCustomTags(), .defaults)
        }
    }

    func testCustomTagAddRejectsEmptySpacesPunctuationAndNonASCII() throws {
        try withTemporaryStore { store, _ in
            XCTAssertThrowsError(
                try store.addCustomTag(
                    emojiID: EmojiID(rawValue: "wave"),
                    tag: "   ",
                    recordID: UUID(),
                    timestamp: .now
                )
            ) { error in
                XCTAssertEqual(error as? CustomTagMutationError, .empty)
            }

            for invalidTag in ["two words", "hello!", "café"] {
                XCTAssertThrowsError(
                    try store.addCustomTag(
                        emojiID: EmojiID(rawValue: "wave"),
                        tag: invalidTag,
                        recordID: UUID(),
                        timestamp: .now
                    )
                ) { error in
                    XCTAssertEqual(error as? CustomTagMutationError, .invalidCharacters)
                }
            }
        }
    }

    func testCommittedTonePreferencesAreIsolatedPerEmojiAndReplaceInPlace() throws {
        let firstID = EmojiID(rawValue: "wave")
        let secondID = EmojiID(rawValue: "thumbs_up")

        try withTemporaryStore { store, _ in
            try store.recordSkinTonePreference(
                emojiID: firstID,
                selectedVariant: "👋🏻",
                commitSucceeded: true,
                updatedAt: Date(timeIntervalSince1970: 1)
            )
            try store.recordSkinTonePreference(
                emojiID: secondID,
                selectedVariant: "👍🏿",
                commitSucceeded: true,
                updatedAt: Date(timeIntervalSince1970: 2)
            )
            try store.recordSkinTonePreference(
                emojiID: firstID,
                selectedVariant: "👋🏽",
                commitSucceeded: true,
                updatedAt: Date(timeIntervalSince1970: 3)
            )

            let preferences = try store.currentSkinTonePreferences().preferences
            XCTAssertEqual(preferences.count, 2)
            XCTAssertEqual(
                preferences.first(where: { $0.emojiID == firstID })?.selectedVariant,
                "👋🏽"
            )
            XCTAssertEqual(
                preferences.first(where: { $0.emojiID == secondID })?.selectedVariant,
                "👍🏿"
            )
        }
    }

    func testFailedOrCancelledToneCommitDoesNotWriteOrNotify() throws {
        let poster = RecordingChangePoster()

        try withTemporaryStore(changePoster: poster) { store, _ in
            try store.recordSkinTonePreference(
                emojiID: EmojiID(rawValue: "wave"),
                selectedVariant: "👋🏽",
                commitSucceeded: false,
                updatedAt: .now
            )

            XCTAssertEqual(try store.currentSkinTonePreferences(), .defaults)
            XCTAssertEqual(poster.postCount, 0)
        }
    }

    func testSuccessfulWritesPostChangeNotifications() throws {
        let poster = RecordingChangePoster()

        try withTemporaryStore(changePoster: poster) { store, _ in
            try store.update { $0.isEnabled = false }
            try store.updateCustomTags { _ in }
            try store.updateSkinTonePreferences { _ in }
            XCTAssertEqual(poster.postCount, 3)
        }
    }

    func testFailedMutationDoesNotReplaceStoredSnapshot() throws {
        try withTemporaryStore { store, _ in
            XCTAssertThrowsError(
                try store.update { snapshot in
                    snapshot.isEnabled = false
                    throw TestFailure.expected
                }
            )
            XCTAssertEqual(try store.currentSnapshot(), .defaults)
        }
    }

    func testConcurrentReadersAndWritersSeeOnlyValidSnapshots() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "ColonSettingsCoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = try ColonLocalStore(
            paths: ColonStoragePaths(rootDirectoryURL: rootURL),
            changePoster: RecordingChangePoster()
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            for iteration in 0..<200 {
                group.addTask {
                    if iteration.isMultiple(of: 2) {
                        try store.update { $0.isEnabled.toggle() }
                    } else {
                        let snapshot = try store.currentSnapshot()
                        guard snapshot.schemaVersion == 1,
                              snapshot.visibleRowCount == 6,
                              snapshot.maximumResultCount == 50,
                              snapshot.enabledApps.count == 8
                        else {
                            throw TestFailure.invalidConcurrentSnapshot
                        }
                    }
                }
            }

            try await group.waitForAll()
        }
    }

    private func withTemporaryStore(
        changePoster: any SettingsChangePosting = RecordingChangePoster(),
        now: @escaping @Sendable () -> Date = { Date() },
        operation: (ColonLocalStore, ColonStoragePaths) throws -> Void
    ) throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "ColonSettingsCoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let paths = ColonStoragePaths(rootDirectoryURL: rootURL)
        let store = try ColonLocalStore(paths: paths, changePoster: changePoster, now: now)
        try operation(store, paths)
    }
}

private enum TestFailure: Error {
    case expected
    case invalidConcurrentSnapshot
}

private final class RecordingChangePoster: SettingsChangePosting, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var postCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func postSettingsChanged() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
