import ColonModels
import Foundation
import XCTest
@testable import ColonSettingsCore

final class InputMethodInstallerTests: XCTestCase {
    func testInstallAndUpgradeReplaceBundleContents() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceV1 = try makeBundle(in: root, name: "v1", version: "1")
        let sourceV2 = try makeBundle(in: root, name: "v2", version: "2")
        let destination = root.appending(path: "Input Methods/Colon.app")
        let installer = InputMethodInstaller(validator: FixtureBundleValidator())

        XCTAssertEqual(
            try installer.install(
                sourceURL: sourceV1,
                destinationURL: destination,
                expectedBundleIdentifier: fixtureBundleID
            ).version,
            "1"
        )
        XCTAssertEqual(try version(at: destination), "1")

        XCTAssertEqual(
            try installer.install(
                sourceURL: sourceV2,
                destinationURL: destination,
                expectedBundleIdentifier: fixtureBundleID
            ).version,
            "2"
        )
        XCTAssertEqual(try version(at: destination), "2")
    }

    func testInvalidSourceDoesNotReplaceExistingInstall() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = try makeBundle(in: root, name: "valid", version: "1")
        let invalid = try makeBundle(
            in: root,
            name: "invalid",
            version: "2",
            signatureValid: false
        )
        let destination = root.appending(path: "Input Methods/Colon.app")
        let installer = InputMethodInstaller(validator: FixtureBundleValidator())
        _ = try installer.install(
            sourceURL: valid,
            destinationURL: destination,
            expectedBundleIdentifier: fixtureBundleID
        )

        XCTAssertThrowsError(
            try installer.install(
                sourceURL: invalid,
                destinationURL: destination,
                expectedBundleIdentifier: fixtureBundleID
            )
        )
        XCTAssertEqual(try version(at: destination), "1")
    }

    func testRollbackFailureRetainsLastKnownGoodBundle() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceV1 = try makeBundle(in: root, name: "v1", version: "1")
        let sourceV2 = try makeBundle(in: root, name: "v2", version: "2")
        let destination = root.appending(path: "Input Methods/Colon.app")
        let fileManager = RollbackFailingFileManager()
        let installer = InputMethodInstaller(
            validator: FixtureBundleValidator(),
            fileManager: fileManager
        )
        _ = try installer.install(
            sourceURL: sourceV1,
            destinationURL: destination,
            expectedBundleIdentifier: fixtureBundleID
        )

        fileManager.failPromotionAndRollback = true
        XCTAssertThrowsError(
            try installer.install(
                sourceURL: sourceV2,
                destinationURL: destination,
                expectedBundleIdentifier: fixtureBundleID
            )
        ) { error in
            XCTAssertEqual(error as? InputMethodInstallError, .rollbackFailed)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let retainedBackups = try FileManager.default.contentsOfDirectory(
            at: destination.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".backup-") }
        let retainedBackup = try XCTUnwrap(retainedBackups.first)
        XCTAssertEqual(try version(at: retainedBackup), "1")
    }

    func testUninstallValidatesIdentityBeforeRemoval() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = try makeBundle(in: root, name: "installed", version: "1")
        let installer = InputMethodInstaller(validator: FixtureBundleValidator())

        XCTAssertThrowsError(
            try installer.uninstall(
                destinationURL: destination,
                expectedBundleIdentifier: "org.example.Wrong"
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))

        try installer.uninstall(
            destinationURL: destination,
            expectedBundleIdentifier: fixtureBundleID
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testOnboardingStagesAreDeterministic() {
        let cases: [(InputMethodReadinessSnapshot, InputMethodOnboardingStage, Bool)] = [
            (.init(isInstalled: false, isDiscovered: false, isEnabled: false, isSelected: false), .notInstalled, false),
            (.init(isInstalled: true, isDiscovered: false, isEnabled: false, isSelected: false), .installedAwaitingDiscovery, true),
            (.init(isInstalled: true, isDiscovered: true, isEnabled: false, isSelected: false), .discoveredDisabled, false),
            (.init(isInstalled: true, isDiscovered: true, isEnabled: true, isSelected: false), .enabledNotSelected, false),
            (.init(isInstalled: true, isDiscovered: true, isEnabled: true, isSelected: true), .ready, false),
        ]
        for (snapshot, stage, requiresLogout) in cases {
            let state = InputMethodOnboardingState(snapshot: snapshot)
            XCTAssertEqual(state.stage, stage)
            XCTAssertEqual(state.requiresLogoutOrLogin, requiresLogout)
        }
    }

    func testDiagnosticBufferIsBoundedAndExportContainsNoTextFields() throws {
        let buffer = DiagnosticEventBuffer(capacity: 2)
        for code in [
            DiagnosticEventCode.installCopyFailed,
            .inputSourceNotDiscovered,
            .commitRangeInvalid,
        ] {
            buffer.append(
                DiagnosticEvent(
                    timestamp: Date(timeIntervalSince1970: 1),
                    subsystem: .installer,
                    code: code
                )
            )
        }
        XCTAssertEqual(buffer.snapshot().map(\.code), [.inputSourceNotDiscovered, .commitRangeInvalid])

        let report = ColonDiagnosticReport(
            generatedAt: Date(timeIntervalSince1970: 2),
            appVersion: "1.0.0 (1)",
            operatingSystemVersion: "26.0",
            inputMethodReadiness: .init(
                isInstalled: true,
                isDiscovered: true,
                isEnabled: false,
                isSelected: false
            ),
            events: buffer.snapshot()
        )
        let data = try DiagnosticReportEncoder().encode(report)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("query"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("typedText"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("textBeforeCaret"))
    }

    private var fixtureBundleID: String { "org.colonproject.inputmethod.Colon" }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "colon-installer-tests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }

    private func makeBundle(
        in root: URL,
        name: String,
        version: String,
        signatureValid: Bool = true
    ) throws -> URL {
        let bundle = root.appending(path: "\(name).app", directoryHint: .isDirectory)
        let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": fixtureBundleID,
            "CFBundleShortVersionString": version,
            "FixtureSignatureValid": signatureValid,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appending(path: "Info.plist"))
        return bundle
    }

    private func version(at url: URL) throws -> String {
        try FixtureBundleValidator().validateBundle(
            at: url,
            expectedBundleIdentifier: fixtureBundleID
        ).version
    }
}

private struct FixtureBundleValidator: InputMethodBundleValidating {
    func validateBundle(
        at url: URL,
        expectedBundleIdentifier: String
    ) throws -> InputMethodBundleIdentity {
        let data = try Data(contentsOf: url.appending(path: "Contents/Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == expectedBundleIdentifier,
              plist["FixtureSignatureValid"] as? Bool == true,
              let version = plist["CFBundleShortVersionString"] as? String
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return InputMethodBundleIdentity(
            bundleIdentifier: expectedBundleIdentifier,
            version: version
        )
    }
}

private final class RollbackFailingFileManager: FileManager {
    var failPromotionAndRollback = false

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if failPromotionAndRollback,
           srcURL.lastPathComponent.contains(".staged-")
                || (failPromotionAndRollback && srcURL.lastPathComponent.contains(".backup-"))
        {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}
