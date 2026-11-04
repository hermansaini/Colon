import Foundation

public struct ColonStoragePaths: Sendable, Equatable {
    public let rootDirectoryURL: URL
    public let settingsURL: URL
    public let customTagsURL: URL
    public let skinTonePreferencesURL: URL
    public let diagnosticsDirectoryURL: URL

    public init(rootDirectoryURL: URL) {
        self.rootDirectoryURL = rootDirectoryURL
        settingsURL = rootDirectoryURL.appending(path: "settings-v1.json", directoryHint: .notDirectory)
        customTagsURL = rootDirectoryURL.appending(path: "custom-tags-v1.json", directoryHint: .notDirectory)
        skinTonePreferencesURL = rootDirectoryURL.appending(path: "skin-tones-v1.json", directoryHint: .notDirectory)
        diagnosticsDirectoryURL = rootDirectoryURL.appending(path: "diagnostics", directoryHint: .isDirectory)
    }

    public static func userApplicationSupport() throws -> Self {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ColonStorageError.applicationSupportDirectoryUnavailable
        }

        return Self(
            rootDirectoryURL: applicationSupportURL.appending(path: "Colon", directoryHint: .isDirectory)
        )
    }
}

public enum ColonStorageDocument: String, Codable, Sendable {
    case settings
    case customTags
    case skinTonePreferences
}

public struct ColonStorageRecoveryNotice: Sendable, Equatable {
    public let document: ColonStorageDocument
    public let backupURL: URL?
    public let recoveredAt: Date

    public init(document: ColonStorageDocument, backupURL: URL?, recoveredAt: Date) {
        self.document = document
        self.backupURL = backupURL
        self.recoveredAt = recoveredAt
    }
}

public enum ColonStorageError: Error, Equatable {
    case applicationSupportDirectoryUnavailable
    case unsupportedSchema(document: ColonStorageDocument, found: Int)
    case invalidSettings
    case invalidCustomTags
    case invalidSkinTonePreferences
}
