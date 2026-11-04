import ColonModels
import Foundation

public protocol ColonSettingsReading: Sendable {
    func currentSnapshot() throws -> ColonSettingsSnapshot
}

public protocol ColonSettingsWriting: Sendable {
    func update(
        _ mutation: @Sendable (inout ColonSettingsSnapshot) throws -> Void
    ) throws
}

public protocol CustomTagsReading: Sendable {
    func currentCustomTags() throws -> CustomTagsSnapshot
}

public protocol CustomTagsWriting: Sendable {
    func updateCustomTags(
        _ mutation: @Sendable (inout CustomTagsSnapshot) throws -> Void
    ) throws
    func addCustomTag(
        emojiID: EmojiID,
        tag: String,
        recordID: UUID,
        timestamp: Date
    ) throws -> CustomTagRecord
    func removeCustomTag(id: UUID) throws
}

public enum CustomTagMutationError: Error, Equatable, Sendable {
    case empty
    case invalidCharacters
    case duplicate
}

public protocol SkinTonePreferencesReading: Sendable {
    func currentSkinTonePreferences() throws -> SkinTonePreferencesSnapshot
}

public protocol SkinTonePreferencesWriting: Sendable {
    func updateSkinTonePreferences(
        _ mutation: @Sendable (inout SkinTonePreferencesSnapshot) throws -> Void
    ) throws
    func recordSkinTonePreference(
        emojiID: EmojiID,
        selectedVariant: String,
        commitSucceeded: Bool,
        updatedAt: Date
    ) throws
}

public final class ColonLocalStore: @unchecked Sendable,
    ColonSettingsReading,
    ColonSettingsWriting,
    CustomTagsReading,
    CustomTagsWriting,
    SkinTonePreferencesReading,
    SkinTonePreferencesWriting
{
    public let paths: ColonStoragePaths

    private let lock = NSLock()
    private let changePoster: any SettingsChangePosting
    private let now: @Sendable () -> Date
    private var recoveryNotices: [ColonStorageRecoveryNotice] = []

    public init(
        paths: ColonStoragePaths,
        changePoster: any SettingsChangePosting = DistributedSettingsChangePoster(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        self.paths = paths
        self.changePoster = changePoster
        self.now = now

        try FileManager.default.createDirectory(
            at: paths.rootDirectoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: paths.diagnosticsDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    public static func userDefault() throws -> ColonLocalStore {
        try ColonLocalStore(paths: .userApplicationSupport())
    }

    public func currentSnapshot() throws -> ColonSettingsSnapshot {
        withLock {
            load(
                ColonSettingsSnapshot.self,
                from: paths.settingsURL,
                document: .settings,
                defaultValue: .defaults,
                validate: Self.validate
            )
        }
    }

    public func update(
        _ mutation: @Sendable (inout ColonSettingsSnapshot) throws -> Void
    ) throws {
        try withLock {
            var snapshot = load(
                ColonSettingsSnapshot.self,
                from: paths.settingsURL,
                document: .settings,
                defaultValue: .defaults,
                validate: Self.validate
            )
            try mutation(&snapshot)
            try Self.validate(snapshot)
            try write(snapshot, to: paths.settingsURL)
        }
        changePoster.postSettingsChanged()
    }

    public func currentCustomTags() throws -> CustomTagsSnapshot {
        withLock {
            load(
                CustomTagsSnapshot.self,
                from: paths.customTagsURL,
                document: .customTags,
                defaultValue: .defaults,
                validate: Self.validate
            )
        }
    }

    public func updateCustomTags(
        _ mutation: @Sendable (inout CustomTagsSnapshot) throws -> Void
    ) throws {
        try withLock {
            var snapshot = load(
                CustomTagsSnapshot.self,
                from: paths.customTagsURL,
                document: .customTags,
                defaultValue: .defaults,
                validate: Self.validate
            )
            try mutation(&snapshot)
            try Self.validate(snapshot)
            try write(snapshot, to: paths.customTagsURL)
        }
        changePoster.postSettingsChanged()
    }

    public func addCustomTag(
        emojiID: EmojiID,
        tag: String,
        recordID: UUID = UUID(),
        timestamp: Date = Date()
    ) throws -> CustomTagRecord {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTag.isEmpty == false else {
            throw CustomTagMutationError.empty
        }
        let normalizedTag = trimmedTag.lowercased()
        guard normalizedTag.unicodeScalars.allSatisfy(Self.isAllowedTagScalar) else {
            throw CustomTagMutationError.invalidCharacters
        }
        let record = CustomTagRecord(
            id: recordID,
            emojiID: emojiID,
            normalizedTag: normalizedTag,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try updateCustomTags { snapshot in
            guard snapshot.records.contains(where: {
                $0.emojiID == emojiID && $0.normalizedTag == normalizedTag
            }) == false else {
                throw CustomTagMutationError.duplicate
            }
            snapshot.records.append(record)
        }
        return record
    }

    public func removeCustomTag(id: UUID) throws {
        try updateCustomTags { snapshot in
            snapshot.records.removeAll { $0.id == id }
        }
    }

    public func currentSkinTonePreferences() throws -> SkinTonePreferencesSnapshot {
        withLock {
            load(
                SkinTonePreferencesSnapshot.self,
                from: paths.skinTonePreferencesURL,
                document: .skinTonePreferences,
                defaultValue: .defaults,
                validate: Self.validate
            )
        }
    }

    public func updateSkinTonePreferences(
        _ mutation: @Sendable (inout SkinTonePreferencesSnapshot) throws -> Void
    ) throws {
        try withLock {
            var snapshot = load(
                SkinTonePreferencesSnapshot.self,
                from: paths.skinTonePreferencesURL,
                document: .skinTonePreferences,
                defaultValue: .defaults,
                validate: Self.validate
            )
            try mutation(&snapshot)
            try Self.validate(snapshot)
            try write(snapshot, to: paths.skinTonePreferencesURL)
        }
        changePoster.postSettingsChanged()
    }

    public func recordSkinTonePreference(
        emojiID: EmojiID,
        selectedVariant: String,
        commitSucceeded: Bool,
        updatedAt: Date = Date()
    ) throws {
        guard commitSucceeded else {
            return
        }

        try updateSkinTonePreferences { snapshot in
            let preference = SkinTonePreference(
                emojiID: emojiID,
                selectedVariant: selectedVariant,
                updatedAt: updatedAt
            )
            if let existingIndex = snapshot.preferences.firstIndex(where: { $0.emojiID == emojiID }) {
                snapshot.preferences[existingIndex] = preference
            } else {
                snapshot.preferences.append(preference)
            }
        }
    }

    public func storageRecoveryNotices() -> [ColonStorageRecoveryNotice] {
        withLock { recoveryNotices }
    }

    private func load<Value>(
        _ type: Value.Type,
        from url: URL,
        document: ColonStorageDocument,
        defaultValue: Value,
        validate: (Value) throws -> Void
    ) -> Value where Value: Codable & Sendable {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return defaultValue
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try Self.makeDecoder().decode(type, from: data)
            try validate(decoded)
            return decoded
        } catch {
            let recoveryDate = now()
            let backupURL = backupCorruptFile(at: url, recoveryDate: recoveryDate)

            if backupURL != nil {
                try? write(defaultValue, to: url)
            }

            recoveryNotices.append(
                ColonStorageRecoveryNotice(
                    document: document,
                    backupURL: backupURL,
                    recoveredAt: recoveryDate
                )
            )
            return defaultValue
        }
    }

    private func write<Value>(_ value: Value, to url: URL) throws where Value: Encodable {
        let data = try Self.makeEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func backupCorruptFile(at url: URL, recoveryDate: Date) -> URL? {
        let timestamp = Int64((recoveryDate.timeIntervalSince1970 * 1_000).rounded())
        let baseName = url.deletingPathExtension().lastPathComponent
        var suffix = 0

        while true {
            let disambiguator = suffix == 0 ? "" : "-\(suffix)"
            let backupURL = paths.rootDirectoryURL.appending(
                path: "\(baseName).corrupt-\(timestamp)\(disambiguator).bak",
                directoryHint: .notDirectory
            )

            if FileManager.default.fileExists(atPath: backupURL.path) {
                suffix += 1
                continue
            }

            do {
                try FileManager.default.moveItem(at: url, to: backupURL)
                return backupURL
            } catch {
                return nil
            }
        }
    }

    private func withLock<Value>(_ operation: () throws -> Value) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func validate(_ snapshot: ColonSettingsSnapshot) throws {
        guard snapshot.schemaVersion == ColonSettingsSnapshot.currentSchemaVersion else {
            throw ColonStorageError.unsupportedSchema(
                document: .settings,
                found: snapshot.schemaVersion
            )
        }

        let supportedIdentifiers = Set(SupportedApplication.allCases.map(\.rawValue))
        guard (1...12).contains(snapshot.visibleRowCount),
              (snapshot.visibleRowCount...100).contains(snapshot.maximumResultCount),
              Set(snapshot.enabledApps.keys) == supportedIdentifiers
        else {
            throw ColonStorageError.invalidSettings
        }
    }

    private static func validate(_ snapshot: CustomTagsSnapshot) throws {
        guard snapshot.schemaVersion == CustomTagsSnapshot.currentSchemaVersion else {
            throw ColonStorageError.unsupportedSchema(
                document: .customTags,
                found: snapshot.schemaVersion
            )
        }

        let ids = Set(snapshot.records.map(\.id))
        let recordsAreValid = snapshot.records.allSatisfy {
            !$0.emojiID.rawValue.isEmpty
                && !$0.normalizedTag.isEmpty
                && $0.normalizedTag == $0.normalizedTag.lowercased()
                && $0.normalizedTag.unicodeScalars.allSatisfy(Self.isAllowedTagScalar)
        }

        guard ids.count == snapshot.records.count, recordsAreValid else {
            throw ColonStorageError.invalidCustomTags
        }
    }

    private static func validate(_ snapshot: SkinTonePreferencesSnapshot) throws {
        guard snapshot.schemaVersion == SkinTonePreferencesSnapshot.currentSchemaVersion else {
            throw ColonStorageError.unsupportedSchema(
                document: .skinTonePreferences,
                found: snapshot.schemaVersion
            )
        }

        let emojiIDs = Set(snapshot.preferences.map(\.emojiID))
        let preferencesAreValid = snapshot.preferences.allSatisfy {
            !$0.emojiID.rawValue.isEmpty && !$0.selectedVariant.isEmpty
        }

        guard emojiIDs.count == snapshot.preferences.count, preferencesAreValid else {
            throw ColonStorageError.invalidSkinTonePreferences
        }
    }

    private static func isAllowedTagScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 48...57, 97...122, 43, 45, 95:
            true
        default:
            false
        }
    }
}
