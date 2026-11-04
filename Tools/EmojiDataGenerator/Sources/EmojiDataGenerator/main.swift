import EmojiDataGeneratorCore
import Foundation

enum CommandMode {
    case generate
    case check
}

do {
    var mode: CommandMode?
    var repositoryRootURL = URL(
        filePath: FileManager.default.currentDirectoryPath,
        directoryHint: .isDirectory
    )
    var arguments = Array(CommandLine.arguments.dropFirst())

    while arguments.isEmpty == false {
        let argument = arguments.removeFirst()
        switch argument {
        case "--generate":
            mode = .generate
        case "--check":
            mode = .check
        case "--root":
            guard arguments.isEmpty == false else {
                throw EmojiDataGeneratorError.generatedFileMissing("Missing value for --root")
            }
            repositoryRootURL = URL(
                filePath: arguments.removeFirst(),
                directoryHint: .isDirectory
            )
        default:
            throw EmojiDataGeneratorError.generatedFileMissing("Unknown argument: \(argument)")
        }
    }

    guard let mode else {
        throw EmojiDataGeneratorError.generatedFileMissing("Specify --generate or --check")
    }

    let generator = EmojiDataGenerator(
        configuration: .standard(repositoryRootURL: repositoryRootURL)
    )
    let artifacts = try generator.generate()

    switch mode {
    case .generate:
        try generator.write(artifacts)
    case .check:
        try generator.check(artifacts)
    }

    let summary = artifacts.summary
    print(
        "Emoji dataset valid: \(summary.emojiCount) entries, "
            + "Unicode Emoji \(summary.unicodeEmojiVersion), "
            + "CLDR \(summary.cldrVersion), "
            + "\(summary.modifierCapableEmojiCount) modifier-capable entries"
    )
} catch {
    FileHandle.standardError.write(Data("EmojiDataGenerator: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
