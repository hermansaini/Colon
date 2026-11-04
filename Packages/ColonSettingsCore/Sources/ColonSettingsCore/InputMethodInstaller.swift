import Foundation

public struct InputMethodBundleIdentity: Equatable, Sendable {
    public let bundleIdentifier: String
    public let version: String

    public init(bundleIdentifier: String, version: String) {
        self.bundleIdentifier = bundleIdentifier
        self.version = version
    }
}

public protocol InputMethodBundleValidating: Sendable {
    func validateBundle(
        at url: URL,
        expectedBundleIdentifier: String
    ) throws -> InputMethodBundleIdentity
}

public enum InputMethodInstallError: Error, Equatable, Sendable {
    case sourceMissing
    case destinationInvalid
    case rollbackFailed
}

public struct InputMethodInstaller {
    private let validator: any InputMethodBundleValidating
    private let fileManager: FileManager

    public init(
        validator: any InputMethodBundleValidating,
        fileManager: FileManager = .default
    ) {
        self.validator = validator
        self.fileManager = fileManager
    }

    @discardableResult
    public func install(
        sourceURL: URL,
        destinationURL: URL,
        expectedBundleIdentifier: String
    ) throws -> InputMethodBundleIdentity {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw InputMethodInstallError.sourceMissing
        }
        _ = try validator.validateBundle(
            at: sourceURL,
            expectedBundleIdentifier: expectedBundleIdentifier
        )

        let parentURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parentURL,
            withIntermediateDirectories: true
        )
        let operationID = UUID().uuidString
        let stagedURL = parentURL.appending(
            path: ".\(destinationURL.lastPathComponent).staged-\(operationID)",
            directoryHint: .isDirectory
        )
        let backupURL = parentURL.appending(
            path: ".\(destinationURL.lastPathComponent).backup-\(operationID)",
            directoryHint: .isDirectory
        )
        var preserveBackup = false
        defer {
            try? fileManager.removeItem(at: stagedURL)
            if preserveBackup == false {
                try? fileManager.removeItem(at: backupURL)
            }
        }

        try fileManager.copyItem(at: sourceURL, to: stagedURL)
        _ = try validator.validateBundle(
            at: stagedURL,
            expectedBundleIdentifier: expectedBundleIdentifier
        )

        let hadExistingInstall = fileManager.fileExists(atPath: destinationURL.path)
        if hadExistingInstall {
            try fileManager.moveItem(at: destinationURL, to: backupURL)
        }
        do {
            try fileManager.moveItem(at: stagedURL, to: destinationURL)
            let identity = try validator.validateBundle(
                at: destinationURL,
                expectedBundleIdentifier: expectedBundleIdentifier
            )
            if hadExistingInstall {
                try fileManager.removeItem(at: backupURL)
            }
            return identity
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            if hadExistingInstall {
                do {
                    try fileManager.moveItem(at: backupURL, to: destinationURL)
                } catch {
                    preserveBackup = true
                    throw InputMethodInstallError.rollbackFailed
                }
            }
            throw error
        }
    }

    public func uninstall(
        destinationURL: URL,
        expectedBundleIdentifier: String
    ) throws {
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }
        _ = try validator.validateBundle(
            at: destinationURL,
            expectedBundleIdentifier: expectedBundleIdentifier
        )
        try fileManager.removeItem(at: destinationURL)
    }
}

public enum InputMethodInstallationLocation: String, Codable, Equatable, Sendable {
    case notInstalled
    case userLibrary
    case systemLibrary
    case managedElsewhere
    case multipleCopies
}

public struct InputMethodReadinessSnapshot: Codable, Equatable, Sendable {
    public let isInstalled: Bool
    public let isDiscovered: Bool
    public let isEnabled: Bool
    public let isSelected: Bool
    public let installationLocation: InputMethodInstallationLocation

    public init(
        isInstalled: Bool,
        isDiscovered: Bool,
        isEnabled: Bool,
        isSelected: Bool,
        installationLocation: InputMethodInstallationLocation = .notInstalled
    ) {
        self.isInstalled = isInstalled
        self.isDiscovered = isDiscovered
        self.isEnabled = isEnabled
        self.isSelected = isSelected
        self.installationLocation = installationLocation
    }
}

public enum InputMethodOnboardingStage: Equatable, Sendable {
    case notInstalled
    case installedAwaitingDiscovery
    case discoveredDisabled
    case enabledNotSelected
    case ready
}

public struct InputMethodOnboardingState: Equatable, Sendable {
    public let stage: InputMethodOnboardingStage
    public let requiresLogoutOrLogin: Bool

    public init(snapshot: InputMethodReadinessSnapshot) {
        if snapshot.isInstalled == false {
            stage = .notInstalled
            requiresLogoutOrLogin = false
        } else if snapshot.isDiscovered == false {
            stage = .installedAwaitingDiscovery
            requiresLogoutOrLogin = true
        } else if snapshot.isEnabled == false {
            stage = .discoveredDisabled
            requiresLogoutOrLogin = false
        } else if snapshot.isSelected == false {
            stage = .enabledNotSelected
            requiresLogoutOrLogin = false
        } else {
            stage = .ready
            requiresLogoutOrLogin = false
        }
    }
}
