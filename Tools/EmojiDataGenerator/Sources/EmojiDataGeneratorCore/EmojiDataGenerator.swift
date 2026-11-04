import ColonModels
import Foundation

public struct EmojiDataGenerationSummary: Sendable, Equatable {
    public let emojiCount: Int
    public let unicodeEmojiVersion: String
    public let cldrVersion: String
    public let modifierCapableEmojiCount: Int

    public init(
        emojiCount: Int,
        unicodeEmojiVersion: String,
        cldrVersion: String,
        modifierCapableEmojiCount: Int
    ) {
        self.emojiCount = emojiCount
        self.unicodeEmojiVersion = unicodeEmojiVersion
        self.cldrVersion = cldrVersion
        self.modifierCapableEmojiCount = modifierCapableEmojiCount
    }
}

public struct GeneratedEmojiDataArtifacts: Sendable {
    public let dataset: EmojiDataset
    public let datasetData: Data
    public let provenanceData: Data
    public let noticesData: Data
    public let summary: EmojiDataGenerationSummary

    public init(
        dataset: EmojiDataset,
        datasetData: Data,
        provenanceData: Data,
        noticesData: Data,
        summary: EmojiDataGenerationSummary
    ) {
        self.dataset = dataset
        self.datasetData = datasetData
        self.provenanceData = provenanceData
        self.noticesData = noticesData
        self.summary = summary
    }
}

public struct EmojiDataGenerator: Sendable {
    public let configuration: EmojiDataGeneratorConfiguration

    public init(configuration: EmojiDataGeneratorConfiguration) {
        self.configuration = configuration
    }

    public func generate() throws -> GeneratedEmojiDataArtifacts {
        let sourceData = try loadAndVerifySources()
        let emojiTestData = try UnicodeEmojiTestParser.parse(
            try requiredData(.unicodeEmojiTest, in: sourceData)
        )

        guard emojiTestData.version == configuration.unicodeEmojiVersion else {
            throw EmojiDataGeneratorError.unicodeVersionMismatch(
                expected: configuration.unicodeEmojiVersion,
                actual: emojiTestData.version
            )
        }

        let cldrAnnotations = try CLDRAnnotationParser.parse([
            try requiredData(.cldrAnnotations, in: sourceData),
            try requiredData(.cldrDerivedAnnotations, in: sourceData),
        ])
        let gemojiByID = try GemojiParser.parse(try requiredData(.gemoji, in: sourceData))
        var gemojiAliasOwners: [String: String] = [:]
        for (emojiID, record) in gemojiByID {
            for alias in record.aliases.map(EmojiTermNormalizer.normalize) where alias.isEmpty == false {
                if let existingOwner = gemojiAliasOwners[alias], existingOwner != emojiID {
                    throw EmojiDataGeneratorError.duplicateAlias(
                        alias: alias,
                        firstID: existingOwner,
                        secondID: emojiID
                    )
                }
                gemojiAliasOwners[alias] = emojiID
            }
        }
        let overrides = try AliasOverridesParser.parse(Data(contentsOf: configuration.overridesURL))
        let officialSkinToneSequenceKeys = try UnicodeEmojiSequenceParser.officialSkinToneSequenceKeys(
            from: [
                try requiredData(.unicodeEmojiSequences, in: sourceData),
                try requiredData(.unicodeEmojiZWJSequences, in: sourceData),
            ]
        )

        let baseEmojiIDs = Set(
            emojiTestData.records
                .filter { EmojiCodePoints.containsSkinToneModifier($0.codePoints) == false }
                .map { EmojiCodePoints.stableID($0.codePoints) }
        )
        let baseEmojiIDByName = Dictionary(
            emojiTestData.records
                .filter { EmojiCodePoints.containsSkinToneModifier($0.codePoints) == false }
                .map { ($0.name, EmojiCodePoints.stableID($0.codePoints)) },
            uniquingKeysWith: { first, _ in first }
        )
        var variantsByBaseEmojiID: [String: [UnicodeEmojiRecord]] = [:]

        for record in emojiTestData.records where EmojiCodePoints.containsSkinToneModifier(record.codePoints) {
            let baseCodePoints = EmojiCodePoints.removingSkinToneModifiers(record.codePoints)
            let structuralBaseEmojiID = EmojiCodePoints.stableID(baseCodePoints)
            let baseName = record.name.split(separator: ":", maxSplits: 1).first.map(String.init)
            let baseEmojiID: String

            if baseEmojiIDs.contains(structuralBaseEmojiID) {
                baseEmojiID = structuralBaseEmojiID
            } else if let baseName, let namedBaseEmojiID = baseEmojiIDByName[baseName] {
                baseEmojiID = namedBaseEmojiID
            } else {
                throw EmojiDataGeneratorError.invalidEntry(structuralBaseEmojiID)
            }
            variantsByBaseEmojiID[baseEmojiID, default: []].append(record)
        }

        let baseRecords = emojiTestData.records.filter {
            EmojiCodePoints.containsSkinToneModifier($0.codePoints) == false
        }
        let generatedCanonicalAliasCounts = Dictionary(
            grouping: baseRecords,
            by: { record in
                EmojiTermNormalizer.normalize(cldrAnnotations[record.emoji]?.name ?? record.name)
            }
        ).mapValues(\.count)
        var usedOverrideIDs: Set<String> = []
        let entries = try baseRecords.enumerated().map { sortOrder, record in
            let emojiID = EmojiCodePoints.stableID(record.codePoints)
            let annotation = cldrAnnotations[record.emoji]
            let canonicalName = annotation?.name ?? record.name
            let generatedCanonicalAlias = EmojiTermNormalizer.normalize(canonicalName)
            let gemoji = gemojiByID[emojiID]
            let override = overrides.entries[emojiID]

            if override != nil {
                usedOverrideIDs.insert(emojiID)
            }

            let generatedAliasOwner = gemojiAliasOwners[generatedCanonicalAlias]
            let generatedAliasBelongsToAnotherEmoji = generatedAliasOwner != nil
                && generatedAliasOwner != emojiID
            let generatedAliasIsAmbiguous = generatedCanonicalAliasCounts[generatedCanonicalAlias, default: 0] > 1
            let generatedAliasNeedsDisambiguation = generatedAliasBelongsToAnotherEmoji
                || generatedAliasIsAmbiguous
            let disambiguatedCanonicalAlias = if generatedAliasNeedsDisambiguation {
                gemoji?.aliases.map(EmojiTermNormalizer.normalize).first(where: {
                    gemojiAliasOwners[$0] == emojiID
                }) ?? generatedCanonicalAlias
            } else {
                generatedCanonicalAlias
            }
            let canonicalAlias = EmojiTermNormalizer.normalize(
                override?.canonicalAlias ?? disambiguatedCanonicalAlias
            )
            var alternateAliases = [generatedCanonicalAlias]
            alternateAliases.append(EmojiTermNormalizer.normalize(record.name))
            alternateAliases.append(contentsOf: gemoji?.aliases.map(EmojiTermNormalizer.normalize) ?? [])
            alternateAliases.append(contentsOf: override?.alternateAliases.map(EmojiTermNormalizer.normalize) ?? [])
            var excludedAliases = Set(
                override?.excludedAliases.map(EmojiTermNormalizer.normalize) ?? []
            )
            if generatedAliasNeedsDisambiguation {
                excludedAliases.insert(generatedCanonicalAlias)
            }
            alternateAliases = stableUnique(alternateAliases).filter {
                $0.isEmpty == false && $0 != canonicalAlias && excludedAliases.contains($0) == false
            }

            var tags = annotation?.tags.map(EmojiTermNormalizer.normalize) ?? []
            tags.append(contentsOf: gemoji?.tags.map(EmojiTermNormalizer.normalize) ?? [])
            tags.append(contentsOf: override?.tags.map(EmojiTermNormalizer.normalize) ?? [])
            let aliasSet = Set([canonicalAlias] + alternateAliases)
            tags = stableUnique(tags).filter { $0.isEmpty == false && aliasSet.contains($0) == false }

            let variants = variantsByBaseEmojiID[emojiID, default: []]
                .sorted { $0.sourceOrder < $1.sourceOrder }
                .map(\.emoji)

            return EmojiEntry(
                id: EmojiID(rawValue: emojiID),
                emoji: record.emoji,
                canonicalName: canonicalName,
                canonicalAlias: canonicalAlias,
                alternateAliases: alternateAliases,
                tags: tags,
                category: try category(from: record.category),
                sortOrder: sortOrder,
                skinToneVariants: [record.emoji] + variants
            )
        }

        if let unknownOverrideID = Set(overrides.entries.keys).subtracting(usedOverrideIDs).sorted().first {
            throw EmojiDataGeneratorError.unknownOverride(unknownOverrideID)
        }

        let dataset = EmojiDataset(
            schemaVersion: EmojiDataset.currentSchemaVersion,
            metadata: EmojiDatasetMetadata(
                unicodeEmojiVersion: configuration.unicodeEmojiVersion,
                cldrVersion: configuration.cldrVersion,
                gemojiCommit: configuration.gemojiCommit,
                generatedAt: configuration.generatedAt
            ),
            entries: entries
        )
        try EmojiDatasetValidator.validate(
            dataset,
            officialSkinToneSequenceKeys: officialSkinToneSequenceKeys
        )

        let datasetData = try encodeDeterministically(dataset)
        let provenance = EmojiDataProvenance(
            schemaVersion: 1,
            generatedAt: configuration.generatedAt,
            datasetSHA256: EmojiDataHashing.sha256Hex(datasetData),
            aliasOverridesSHA256: EmojiDataHashing.sha256Hex(
                try Data(contentsOf: configuration.overridesURL)
            ),
            sources: configuration.sources
        )
        let provenanceData = try encodeDeterministically(provenance)
        let noticesData = Data(makeThirdPartyNotices().utf8)
        let summary = EmojiDataGenerationSummary(
            emojiCount: entries.count,
            unicodeEmojiVersion: configuration.unicodeEmojiVersion,
            cldrVersion: configuration.cldrVersion,
            modifierCapableEmojiCount: entries.count(where: { $0.skinToneVariants.count > 1 })
        )

        return GeneratedEmojiDataArtifacts(
            dataset: dataset,
            datasetData: datasetData,
            provenanceData: provenanceData,
            noticesData: noticesData,
            summary: summary
        )
    }

    public func write(_ artifacts: GeneratedEmojiDataArtifacts) throws {
        try FileManager.default.createDirectory(
            at: configuration.datasetOutputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: configuration.packageDatasetOutputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try artifacts.datasetData.write(to: configuration.datasetOutputURL, options: .atomic)
        try artifacts.datasetData.write(to: configuration.packageDatasetOutputURL, options: .atomic)
        try artifacts.provenanceData.write(to: configuration.provenanceOutputURL, options: .atomic)
        try artifacts.noticesData.write(to: configuration.noticesOutputURL, options: .atomic)
    }

    public func check(_ artifacts: GeneratedEmojiDataArtifacts) throws {
        try check(artifacts.datasetData, against: configuration.datasetOutputURL)
        try check(artifacts.datasetData, against: configuration.packageDatasetOutputURL)
        try check(artifacts.provenanceData, against: configuration.provenanceOutputURL)
        try check(artifacts.noticesData, against: configuration.noticesOutputURL)
    }

    private func loadAndVerifySources() throws -> [EmojiDataSourceKind: Data] {
        var result: [EmojiDataSourceKind: Data] = [:]

        for source in configuration.sources {
            let data = try Data(contentsOf: configuration.url(for: source))
            let actualHash = EmojiDataHashing.sha256Hex(data)
            guard actualHash == source.sha256 else {
                throw EmojiDataGeneratorError.checksumMismatch(
                    kind: source.kind,
                    expected: source.sha256,
                    actual: actualHash
                )
            }
            result[source.kind] = data
        }

        return result
    }

    private func requiredData(
        _ kind: EmojiDataSourceKind,
        in sourceData: [EmojiDataSourceKind: Data]
    ) throws -> Data {
        guard let data = sourceData[kind] else {
            throw EmojiDataGeneratorError.missingConfiguredSource(kind)
        }
        return data
    }

    private func category(from sourceCategory: String) throws -> EmojiCategory {
        switch sourceCategory {
        case "Smileys & Emotion": .smileysAndEmotion
        case "People & Body": .peopleAndBody
        case "Component": .component
        case "Animals & Nature": .animalsAndNature
        case "Food & Drink": .foodAndDrink
        case "Travel & Places": .travelAndPlaces
        case "Activities": .activities
        case "Objects": .objects
        case "Symbols": .symbols
        case "Flags": .flags
        default: throw EmojiDataGeneratorError.unsupportedUnicodeCategory(sourceCategory)
        }
    }

    private func encodeDeterministically<Value>(_ value: Value) throws -> Data where Value: Encodable {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    private func check(_ expectedData: Data, against url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EmojiDataGeneratorError.generatedFileMissing(url.path)
        }
        guard try Data(contentsOf: url) == expectedData else {
            throw EmojiDataGeneratorError.generatedFileOutOfDate(url.path)
        }
    }

    private func makeThirdPartyNotices() -> String {
        """
        # Third-Party Notices

        Colon's generated emoji metadata incorporates data from the following pinned build-time sources. Colon includes no third-party emoji artwork and performs no runtime data downloads.

        ## Unicode Emoji 17.0 and CLDR 48

        Copyright © 1991–2026 Unicode, Inc. All rights reserved. Distributed under the Unicode License V3 included at `Vendor/Unicode/LICENSE.txt` and `Vendor/CLDR/LICENSE`.

        - Unicode Emoji 17.0 data: <https://www.unicode.org/Public/17.0.0/emoji/>
        - CLDR 48 English annotations: <https://github.com/unicode-org/cldr/tree/release-48>

        ## GitHub gemoji

        The alias/tag snapshot comes from GitHub's `gemoji` project at commit `\(configuration.gemojiCommit)`, distributed under the MIT License included at `Vendor/gemoji/\(configuration.gemojiCommit)/LICENSE`.

        - Repository: <https://github.com/github/gemoji>

        Exact source paths and SHA-256 checksums are recorded in `Vendor/SOURCES.md` and `Resources/Generated/emoji-index.provenance.json`.
        """ + "\n"
    }
}

private struct EmojiDataProvenance: Encodable {
    let schemaVersion: Int
    let generatedAt: String
    let datasetSHA256: String
    let aliasOverridesSHA256: String
    let sources: [PinnedEmojiDataSource]
}
