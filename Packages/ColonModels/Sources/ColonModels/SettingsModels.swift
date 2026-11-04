import Foundation

public enum SupportedApplication: String, CaseIterable, Codable, Sendable, Identifiable {
    case messages = "com.apple.MobileSMS"
    case notes = "com.apple.Notes"
    case mail = "com.apple.mail"
    case safari = "com.apple.Safari"
    case chrome = "com.google.Chrome"
    case slack = "com.tinyspeck.slackmacgap"
    case discord = "com.hnc.Discord"
    case notion = "notion.id"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .messages: "Messages"
        case .notes: "Notes"
        case .mail: "Mail"
        case .safari: "Safari"
        case .chrome: "Google Chrome"
        case .slack: "Slack"
        case .discord: "Discord"
        case .notion: "Notion"
        }
    }
}

public enum AppearancePreference: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark
}

public enum PickerSize: String, CaseIterable, Codable, Sendable {
    case compact
    case standard
    case large
}

public struct ColonSettingsSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var isEnabled: Bool
    public var launchAtLoginPreferred: Bool
    public var menuBarVisible: Bool
    public var appearance: AppearancePreference
    public var pickerSize: PickerSize
    public var visibleRowCount: Int
    public var maximumResultCount: Int
    public var enabledApps: [String: Bool]

    public init(
        schemaVersion: Int,
        isEnabled: Bool,
        launchAtLoginPreferred: Bool,
        menuBarVisible: Bool,
        appearance: AppearancePreference,
        pickerSize: PickerSize,
        visibleRowCount: Int,
        maximumResultCount: Int,
        enabledApps: [String: Bool]
    ) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.launchAtLoginPreferred = launchAtLoginPreferred
        self.menuBarVisible = menuBarVisible
        self.appearance = appearance
        self.pickerSize = pickerSize
        self.visibleRowCount = visibleRowCount
        self.maximumResultCount = maximumResultCount
        self.enabledApps = enabledApps
    }

    public static var defaults: Self {
        Self(
            schemaVersion: currentSchemaVersion,
            isEnabled: true,
            launchAtLoginPreferred: true,
            menuBarVisible: true,
            appearance: .system,
            pickerSize: .standard,
            visibleRowCount: 6,
            maximumResultCount: 50,
            enabledApps: Dictionary(
                uniqueKeysWithValues: SupportedApplication.allCases.map { ($0.rawValue, true) }
            )
        )
    }
}

public struct CustomTagRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let emojiID: EmojiID
    public var normalizedTag: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        emojiID: EmojiID,
        normalizedTag: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.emojiID = emojiID
        self.normalizedTag = normalizedTag
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CustomTagsSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var records: [CustomTagRecord]

    public init(schemaVersion: Int, records: [CustomTagRecord]) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    public static var defaults: Self {
        Self(schemaVersion: currentSchemaVersion, records: [])
    }
}

public struct SkinTonePreference: Codable, Sendable, Hashable {
    public let emojiID: EmojiID
    public var selectedVariant: String
    public var updatedAt: Date

    public init(emojiID: EmojiID, selectedVariant: String, updatedAt: Date) {
        self.emojiID = emojiID
        self.selectedVariant = selectedVariant
        self.updatedAt = updatedAt
    }
}

public struct SkinTonePreferencesSnapshot: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var preferences: [SkinTonePreference]

    public init(schemaVersion: Int, preferences: [SkinTonePreference]) {
        self.schemaVersion = schemaVersion
        self.preferences = preferences
    }

    public static var defaults: Self {
        Self(schemaVersion: currentSchemaVersion, preferences: [])
    }
}
