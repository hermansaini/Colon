import Foundation

public enum EmojiDataSourceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case unicodeEmojiTest
    case unicodeEmojiSequences
    case unicodeEmojiZWJSequences
    case cldrAnnotations
    case cldrDerivedAnnotations
    case gemoji
    case slackEmojiData
}

public struct PinnedEmojiDataSource: Codable, Sendable, Equatable {
    public let kind: EmojiDataSourceKind
    public let name: String
    public let version: String
    public let relativePath: String
    public let sourceURL: String
    public let licenseRelativePath: String
    public let sha256: String

    public init(
        kind: EmojiDataSourceKind,
        name: String,
        version: String,
        relativePath: String,
        sourceURL: String,
        licenseRelativePath: String,
        sha256: String
    ) {
        self.kind = kind
        self.name = name
        self.version = version
        self.relativePath = relativePath
        self.sourceURL = sourceURL
        self.licenseRelativePath = licenseRelativePath
        self.sha256 = sha256
    }
}

public struct EmojiDataGeneratorConfiguration: Sendable {
    public let repositoryRootURL: URL
    public let unicodeEmojiVersion: String
    public let cldrVersion: String
    public let gemojiCommit: String
    public let generatedAt: String
    public let sources: [PinnedEmojiDataSource]
    public let overridesURL: URL
    public let datasetOutputURL: URL
    public let packageDatasetOutputURL: URL
    public let provenanceOutputURL: URL
    public let noticesOutputURL: URL

    public init(
        repositoryRootURL: URL,
        unicodeEmojiVersion: String,
        cldrVersion: String,
        gemojiCommit: String,
        generatedAt: String,
        sources: [PinnedEmojiDataSource],
        overridesURL: URL,
        datasetOutputURL: URL,
        packageDatasetOutputURL: URL,
        provenanceOutputURL: URL,
        noticesOutputURL: URL
    ) {
        self.repositoryRootURL = repositoryRootURL
        self.unicodeEmojiVersion = unicodeEmojiVersion
        self.cldrVersion = cldrVersion
        self.gemojiCommit = gemojiCommit
        self.generatedAt = generatedAt
        self.sources = sources
        self.overridesURL = overridesURL
        self.datasetOutputURL = datasetOutputURL
        self.packageDatasetOutputURL = packageDatasetOutputURL
        self.provenanceOutputURL = provenanceOutputURL
        self.noticesOutputURL = noticesOutputURL
    }

    public static func standard(repositoryRootURL: URL) -> Self {
        let gemojiCommit = "0eca75db9301421efc8710baf7a7576793ae452a"

        return Self(
            repositoryRootURL: repositoryRootURL,
            unicodeEmojiVersion: "17.0",
            cldrVersion: "48",
            gemojiCommit: gemojiCommit,
            generatedAt: "2026-06-26T00:00:00Z",
            sources: [
                PinnedEmojiDataSource(
                    kind: .unicodeEmojiTest,
                    name: "Unicode emoji-test.txt",
                    version: "17.0",
                    relativePath: "Vendor/Unicode/17.0.0/emoji-test.txt",
                    sourceURL: "https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt",
                    licenseRelativePath: "Vendor/Unicode/LICENSE.txt",
                    sha256: "1d8a944f88d7952f7ef7c5167fef3c67995bcae24543949710231b03a201acda"
                ),
                PinnedEmojiDataSource(
                    kind: .unicodeEmojiSequences,
                    name: "Unicode emoji-sequences.txt",
                    version: "17.0",
                    relativePath: "Vendor/Unicode/17.0.0/emoji-sequences.txt",
                    sourceURL: "https://www.unicode.org/Public/17.0.0/emoji/emoji-sequences.txt",
                    licenseRelativePath: "Vendor/Unicode/LICENSE.txt",
                    sha256: "12cc8267dc33cbd11ed32bcf6fc5dc2ad9c7a77bae1bdfba2f41b1b9b3ead8dd"
                ),
                PinnedEmojiDataSource(
                    kind: .unicodeEmojiZWJSequences,
                    name: "Unicode emoji-zwj-sequences.txt",
                    version: "17.0",
                    relativePath: "Vendor/Unicode/17.0.0/emoji-zwj-sequences.txt",
                    sourceURL: "https://www.unicode.org/Public/17.0.0/emoji/emoji-zwj-sequences.txt",
                    licenseRelativePath: "Vendor/Unicode/LICENSE.txt",
                    sha256: "5b25441daed2322b068c5e70cda522946a4f0274df864445a1965a92e5fc5cad"
                ),
                PinnedEmojiDataSource(
                    kind: .cldrAnnotations,
                    name: "CLDR English annotations",
                    version: "48",
                    relativePath: "Vendor/CLDR/48/annotations/en.xml",
                    sourceURL: "https://github.com/unicode-org/cldr/blob/release-48/common/annotations/en.xml",
                    licenseRelativePath: "Vendor/CLDR/LICENSE",
                    sha256: "8511aadd046fdba2f0ffe590266ced8bbf48175ad139b2675d85d7141057b235"
                ),
                PinnedEmojiDataSource(
                    kind: .cldrDerivedAnnotations,
                    name: "CLDR English derived annotations",
                    version: "48",
                    relativePath: "Vendor/CLDR/48/annotationsDerived/en.xml",
                    sourceURL: "https://github.com/unicode-org/cldr/blob/release-48/common/annotationsDerived/en.xml",
                    licenseRelativePath: "Vendor/CLDR/LICENSE",
                    sha256: "d76bd041c8c9e7b00b716aff8b7d9dbf509877010e191d5efd068be2553e066e"
                ),
                PinnedEmojiDataSource(
                    kind: .slackEmojiData,
                    name: "Slack-compatible iamcal emoji-data shortcodes",
                    version: "e77759c296ed37beb0dbd63908b43d8619509c6d",
                    relativePath: "Vendor/emoji-data/e77759c296ed37beb0dbd63908b43d8619509c6d/emoji.json",
                    sourceURL: "https://github.com/iamcal/emoji-data/blob/e77759c296ed37beb0dbd63908b43d8619509c6d/emoji.json",
                    licenseRelativePath: "Vendor/emoji-data/e77759c296ed37beb0dbd63908b43d8619509c6d/LICENSE",
                    sha256: "8736d721991e48c41c57acc46b65e5d32258a45e4bcdebcc6012f420f81e775d"
                ),
                PinnedEmojiDataSource(
                    kind: .gemoji,
                    name: "GitHub gemoji emoji.json",
                    version: gemojiCommit,
                    relativePath: "Vendor/gemoji/\(gemojiCommit)/emoji.json",
                    sourceURL: "https://github.com/github/gemoji/blob/\(gemojiCommit)/db/emoji.json",
                    licenseRelativePath: "Vendor/gemoji/\(gemojiCommit)/LICENSE",
                    sha256: "b174ae2aeb321b52f64adb9ff412f966a7f338839d780784dd15dcad702c2dd6"
                ),
            ],
            overridesURL: repositoryRootURL.appending(
                path: "Resources/Overrides/alias-overrides.json",
                directoryHint: .notDirectory
            ),
            datasetOutputURL: repositoryRootURL.appending(
                path: "Resources/Generated/emoji-index.json",
                directoryHint: .notDirectory
            ),
            packageDatasetOutputURL: repositoryRootURL.appending(
                path: "Packages/ColonEmojiData/Sources/ColonEmojiData/Resources/emoji-index.json",
                directoryHint: .notDirectory
            ),
            provenanceOutputURL: repositoryRootURL.appending(
                path: "Resources/Generated/emoji-index.provenance.json",
                directoryHint: .notDirectory
            ),
            noticesOutputURL: repositoryRootURL.appending(
                path: "THIRD_PARTY_NOTICES.md",
                directoryHint: .notDirectory
            )
        )
    }

    func source(for kind: EmojiDataSourceKind) throws -> PinnedEmojiDataSource {
        guard let source = sources.first(where: { $0.kind == kind }) else {
            throw EmojiDataGeneratorError.missingConfiguredSource(kind)
        }
        return source
    }

    func url(for source: PinnedEmojiDataSource) -> URL {
        repositoryRootURL.appending(path: source.relativePath, directoryHint: .notDirectory)
    }
}
