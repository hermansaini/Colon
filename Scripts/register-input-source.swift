import Carbon.HIToolbox
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(
        Data("Usage: register-input-source.swift <bundle-path>\n".utf8)
    )
    exit(EXIT_FAILURE)
}

let bundleURL = URL(fileURLWithPath: CommandLine.arguments[1])
let status = TISRegisterInputSource(bundleURL as CFURL)

guard status == noErr else {
    FileHandle.standardError.write(
        Data("TISRegisterInputSource failed with status \(status).\n".utf8)
    )
    exit(EXIT_FAILURE)
}

print("Registered \(bundleURL.path) with Text Input Services.")
