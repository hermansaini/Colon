import Carbon.HIToolbox
import ColonSettingsCore
import Foundation
import Security

enum InputMethodInstallationControllerError: Error {
    case systemManagedInstall
    case multipleCopies
    case noEnabledFallbackInputSource
    case fallbackSelectionFailed
}

enum ProductionInputMethodValidationError: Error {
    case invalidBundle
    case invalidSignature(OSStatus)
    case missingTeamIdentifier
    case teamIdentifierMismatch
}

struct ProductionInputMethodBundleValidator: InputMethodBundleValidating {
    func validateBundle(
        at url: URL,
        expectedBundleIdentifier: String
    ) throws -> InputMethodBundleIdentity {
        guard let bundle = Bundle(url: url),
              bundle.bundleIdentifier == expectedBundleIdentifier,
              let version = bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
              ) as? String,
              bundle.executableURL != nil
        else {
            throw ProductionInputMethodValidationError.invalidBundle
        }

        var staticCode: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard status == errSecSuccess, let staticCode else {
            throw ProductionInputMethodValidationError.invalidSignature(status)
        }
        var requirement: SecRequirement?
        status = SecRequirementCreateWithString(
            "anchor apple generic" as CFString,
            [],
            &requirement
        )
        guard status == errSecSuccess, let requirement else {
            throw ProductionInputMethodValidationError.invalidSignature(status)
        }
        status = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: kSecCSStrictValidate),
            requirement
        )
        guard status == errSecSuccess else {
            throw ProductionInputMethodValidationError.invalidSignature(status)
        }

        guard let bundleTeam = teamIdentifier(for: staticCode),
              let companionTeam = companionTeamIdentifier()
        else {
            throw ProductionInputMethodValidationError.missingTeamIdentifier
        }
        guard bundleTeam == companionTeam else {
            throw ProductionInputMethodValidationError.teamIdentifierMismatch
        }
        return InputMethodBundleIdentity(
            bundleIdentifier: expectedBundleIdentifier,
            version: version
        )
    }

    private func teamIdentifier(for code: SecStaticCode) -> String? {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
              let information = information as? [String: Any]
        else {
            return nil
        }
        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private func companionTeamIdentifier() -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            Bundle.main.bundleURL as CFURL,
            [],
            &staticCode
        ) == errSecSuccess,
              let staticCode
        else {
            return nil
        }
        return teamIdentifier(for: staticCode)
    }
}

@MainActor
final class InputMethodInstallationController {
    static let bundleIdentifier = "org.colonproject.inputmethod.Colon"
    static let bundleName = "ColonInputMethod.app"
    static let systemInstalledBundleURL = URL(
        fileURLWithPath: "/Library/Input Methods/\(bundleName)",
        isDirectory: true
    )

    private let fileManager = FileManager.default
    private let validator = ProductionInputMethodBundleValidator()

    var embeddedBundleURL: URL {
        Bundle.main.bundleURL.appending(
            path: "Contents/Library/Input Methods/\(Self.bundleName)",
            directoryHint: .isDirectory
        )
    }

    var installedBundleURL: URL {
        fileManager.homeDirectoryForCurrentUser.appending(
            path: "Library/Input Methods/\(Self.bundleName)",
            directoryHint: .isDirectory
        )
    }

    func install() throws {
        switch installationLocation() {
        case .systemLibrary, .managedElsewhere:
            throw InputMethodInstallationControllerError.systemManagedInstall
        case .multipleCopies:
            throw InputMethodInstallationControllerError.multipleCopies
        case .notInstalled, .userLibrary:
            break
        }
        let installer = InputMethodInstaller(validator: validator)
        try installer.install(
            sourceURL: embeddedBundleURL,
            destinationURL: installedBundleURL,
            expectedBundleIdentifier: Self.bundleIdentifier
        )
        let status = TISRegisterInputSource(installedBundleURL as CFURL)
        guard status == noErr else {
            throw CocoaError(.featureUnsupported)
        }
    }

    func enableAndSelect() throws {
        guard installationLocation() != .multipleCopies else {
            throw InputMethodInstallationControllerError.multipleCopies
        }
        guard let source = matchingInputSources().first else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard TISEnableInputSource(source) == noErr,
              TISSelectInputSource(source) == noErr
        else {
            throw CocoaError(.featureUnsupported)
        }
    }

    func uninstall() throws {
        switch installationLocation() {
        case .systemLibrary, .managedElsewhere:
            throw InputMethodInstallationControllerError.systemManagedInstall
        case .multipleCopies:
            throw InputMethodInstallationControllerError.multipleCopies
        case .notInstalled:
            return
        case .userLibrary:
            break
        }

        let selectedSource = currentInputSource()
        let shouldRestoreColonSelection = selectedSource.map {
            inputSourceID($0) == Self.bundleIdentifier
        } ?? false
        if shouldRestoreColonSelection {
            guard let fallback = allInputSources().first(where: {
                inputSourceID($0) != Self.bundleIdentifier
                    && boolProperty($0, key: kTISPropertyInputSourceIsEnabled)
                    && boolProperty($0, key: kTISPropertyInputSourceIsSelectCapable)
                    && stringProperty($0, key: kTISPropertyInputSourceCategory)
                        == (kTISCategoryKeyboardInputSource as String)
            }) else {
                throw InputMethodInstallationControllerError.noEnabledFallbackInputSource
            }
            guard TISSelectInputSource(fallback) == noErr else {
                throw InputMethodInstallationControllerError.fallbackSelectionFailed
            }
        }

        let installer = InputMethodInstaller(validator: validator)
        do {
            try installer.uninstall(
                destinationURL: installedBundleURL,
                expectedBundleIdentifier: Self.bundleIdentifier
            )
        } catch {
            if shouldRestoreColonSelection, let selectedSource {
                _ = TISSelectInputSource(selectedSource)
            }
            throw error
        }
    }

    func readiness() -> InputMethodReadinessSnapshot {
        let sources = matchingInputSources()
        let location = installationLocation(sources: sources)
        let isInstalled = location != .notInstalled
        let isDiscovered = sources.isEmpty == false
        let isEnabled = sources.contains { boolProperty($0, key: kTISPropertyInputSourceIsEnabled) }
        let selectedID = TISCopyCurrentKeyboardInputSource()
            .map { inputSourceID($0.takeRetainedValue()) }
            ?? nil
        return InputMethodReadinessSnapshot(
            isInstalled: isInstalled,
            isDiscovered: isDiscovered,
            isEnabled: isEnabled,
            isSelected: selectedID == Self.bundleIdentifier,
            installationLocation: location
        )
    }

    private func installationLocation(
        sources: [TISInputSource]? = nil
    ) -> InputMethodInstallationLocation {
        let userBundleExists = hasExpectedBundle(at: installedBundleURL)
        let systemBundleExists = hasExpectedBundle(at: Self.systemInstalledBundleURL)
        let hasOtherDiscoveredBundle = userBundleExists == false
            && systemBundleExists == false
            && (sources ?? matchingInputSources()).isEmpty == false

        if userBundleExists && (systemBundleExists || hasOtherDiscoveredBundle) {
            return .multipleCopies
        }
        if userBundleExists {
            return .userLibrary
        }
        if systemBundleExists {
            return .systemLibrary
        }
        if hasOtherDiscoveredBundle {
            return .managedElsewhere
        }
        return .notInstalled
    }

    private func hasExpectedBundle(at url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              let bundle = Bundle(url: url)
        else {
            return false
        }
        return bundle.bundleIdentifier == Self.bundleIdentifier
    }

    private func matchingInputSources() -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceID as String: Self.bundleIdentifier] as CFDictionary
        guard let unmanagedSources = TISCreateInputSourceList(filter, true) else {
            return []
        }
        return sources(from: unmanagedSources.takeRetainedValue())
    }

    private func allInputSources() -> [TISInputSource] {
        guard let unmanagedSources = TISCreateInputSourceList(nil, true) else {
            return []
        }
        return sources(from: unmanagedSources.takeRetainedValue())
    }

    private func sources(from sources: CFArray) -> [TISInputSource] {
        (0..<CFArrayGetCount(sources)).map { index in
            unsafeBitCast(
                CFArrayGetValueAtIndex(sources, index),
                to: TISInputSource.self
            )
        }
    }

    private func currentInputSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    private func inputSourceID(_ source: TISInputSource) -> String? {
        stringProperty(source, key: kTISPropertyInputSourceID)
    }

    private func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func boolProperty(_ source: TISInputSource, key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return false
        }
        let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }
}
