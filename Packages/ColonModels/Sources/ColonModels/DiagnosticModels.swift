import Foundation

public enum DiagnosticSubsystem: String, CaseIterable, Codable, Sendable {
    case installer
    case inputMethod
    case clientPolicy
    case dataset
    case settings
    case userInterface
}

public enum DiagnosticEventCode: String, CaseIterable, Codable, Sendable {
    case installSourceSignatureInvalid = "INSTALL_SOURCE_SIGNATURE_INVALID"
    case installCopyFailed = "INSTALL_COPY_FAILED"
    case inputSourceNotDiscovered = "INPUT_SOURCE_NOT_DISCOVERED"
    case clientIdentityUnknown = "CLIENT_IDENTITY_UNKNOWN"
    case caretRectUnavailable = "CARET_RECT_UNAVAILABLE"
    case commitRangeInvalid = "COMMIT_RANGE_INVALID"
    case commitClientChanged = "COMMIT_CLIENT_CHANGED"
    case datasetLoadFailed = "DATASET_LOAD_FAILED"
    case settingsCorruptRecovered = "SETTINGS_CORRUPT_RECOVERED"
}

public struct DiagnosticVersion: Codable, Sendable, Equatable {
    public let major: UInt
    public let minor: UInt
    public let patch: UInt
    public let build: UInt?

    public init(major: UInt, minor: UInt, patch: UInt, build: UInt? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.build = build
    }
}

public enum DiagnosticStatus: String, CaseIterable, Codable, Sendable {
    case enabled
    case disabled
    case installed
    case discovered
    case notDiscovered
    case notEnabled
    case selected
    case notSelected
    case recovered
    case failed
}

public enum DiagnosticErrorDomain: String, CaseIterable, Codable, Sendable {
    case installer
    case inputMethod
    case clientPolicy
    case dataset
    case settings
    case userInterface
}

public enum DiagnosticArchitecture: String, CaseIterable, Codable, Sendable {
    case arm64
    case x86_64
}

public struct DiagnosticMetadata: Codable, Sendable, Equatable {
    public let clientApplication: SupportedApplication?
    public let operatingSystemVersion: DiagnosticVersion?
    public let appVersion: DiagnosticVersion?
    public let inputMethodVersion: DiagnosticVersion?
    public let datasetVersion: DiagnosticVersion?
    public let status: DiagnosticStatus?
    public let errorDomain: DiagnosticErrorDomain?
    public let numericErrorCode: Int?
    public let architecture: DiagnosticArchitecture?

    public init(
        clientApplication: SupportedApplication? = nil,
        operatingSystemVersion: DiagnosticVersion? = nil,
        appVersion: DiagnosticVersion? = nil,
        inputMethodVersion: DiagnosticVersion? = nil,
        datasetVersion: DiagnosticVersion? = nil,
        status: DiagnosticStatus? = nil,
        errorDomain: DiagnosticErrorDomain? = nil,
        numericErrorCode: Int? = nil,
        architecture: DiagnosticArchitecture? = nil
    ) {
        self.clientApplication = clientApplication
        self.operatingSystemVersion = operatingSystemVersion
        self.appVersion = appVersion
        self.inputMethodVersion = inputMethodVersion
        self.datasetVersion = datasetVersion
        self.status = status
        self.errorDomain = errorDomain
        self.numericErrorCode = numericErrorCode
        self.architecture = architecture
    }

    public init(from decoder: Decoder) throws {
        let dynamicContainer = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowedKeys = Set(CodingKeys.allCases.map(\.stringValue))

        if let rejectedKey = dynamicContainer.allKeys.first(where: { !allowedKeys.contains($0.stringValue) }) {
            throw DecodingError.dataCorruptedError(
                forKey: rejectedKey,
                in: dynamicContainer,
                debugDescription: "Diagnostic metadata contains a non-allowlisted field."
            )
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientApplication = try container.decodeIfPresent(SupportedApplication.self, forKey: .clientApplication)
        operatingSystemVersion = try container.decodeIfPresent(DiagnosticVersion.self, forKey: .operatingSystemVersion)
        appVersion = try container.decodeIfPresent(DiagnosticVersion.self, forKey: .appVersion)
        inputMethodVersion = try container.decodeIfPresent(DiagnosticVersion.self, forKey: .inputMethodVersion)
        datasetVersion = try container.decodeIfPresent(DiagnosticVersion.self, forKey: .datasetVersion)
        status = try container.decodeIfPresent(DiagnosticStatus.self, forKey: .status)
        errorDomain = try container.decodeIfPresent(DiagnosticErrorDomain.self, forKey: .errorDomain)
        numericErrorCode = try container.decodeIfPresent(Int.self, forKey: .numericErrorCode)
        architecture = try container.decodeIfPresent(DiagnosticArchitecture.self, forKey: .architecture)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case clientApplication
        case operatingSystemVersion
        case appVersion
        case inputMethodVersion
        case datasetVersion
        case status
        case errorDomain
        case numericErrorCode
        case architecture
    }
}

public struct DiagnosticEvent: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let subsystem: DiagnosticSubsystem
    public let code: DiagnosticEventCode
    public let metadata: DiagnosticMetadata

    public init(
        timestamp: Date,
        subsystem: DiagnosticSubsystem,
        code: DiagnosticEventCode,
        metadata: DiagnosticMetadata = DiagnosticMetadata()
    ) {
        self.timestamp = timestamp
        self.subsystem = subsystem
        self.code = code
        self.metadata = metadata
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
