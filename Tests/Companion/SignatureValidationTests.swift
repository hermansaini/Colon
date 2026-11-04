import Foundation
import Testing
@testable import ColonCompanion

@Test func installerRejectsAdHocSignedInputMethod() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let bundle = root.appendingPathComponent("Fixture.app")
    let contents = bundle.appendingPathComponent("Contents")
    let binaries = contents.appendingPathComponent("MacOS")
    try FileManager.default.createDirectory(at: binaries, withIntermediateDirectories: true)
    try FileManager.default.copyItem(
        at: URL(fileURLWithPath: "/usr/bin/true"),
        to: binaries.appendingPathComponent("Fixture")
    )
    let identifier = "org.colonproject.tests.inputmethod"
    let plist: [String: Any] = [
        "CFBundleExecutable": "Fixture",
        "CFBundleIdentifier": identifier,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = ["--force", "--sign", "-", bundle.path]
    let errors = Pipe()
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    try #require(process.terminationStatus == 0)
    do {
        _ = try ProductionInputMethodBundleValidator().validateBundle(
            at: bundle, expectedBundleIdentifier: identifier
        )
        Issue.record("An ad-hoc signature must not be accepted as Apple-issued code")
    } catch ProductionInputMethodValidationError.invalidSignature {
        // The Apple trust requirement must reject it before comparing team IDs.
    } catch {
        Issue.record("Expected invalidSignature, got \(error)")
    }
}
