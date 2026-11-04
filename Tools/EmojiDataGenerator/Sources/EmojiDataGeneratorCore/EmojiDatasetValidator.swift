import ColonModels

public enum EmojiDatasetValidator {
    public static func validate(
        _ dataset: EmojiDataset,
        officialSkinToneSequenceKeys: Set<String>
    ) throws {
        guard dataset.schemaVersion == EmojiDataset.currentSchemaVersion else {
            throw EmojiDataGeneratorError.invalidEntry("dataset-schema")
        }

        var emojiIDs: Set<EmojiID> = []
        var aliasOwners: [String: EmojiID] = [:]
        var sortOrders: Set<Int> = []

        for entry in dataset.entries {
            guard emojiIDs.insert(entry.id).inserted else {
                throw EmojiDataGeneratorError.duplicateEmojiID(entry.id.rawValue)
            }

            guard sortOrders.insert(entry.sortOrder).inserted,
                  entry.id.rawValue == EmojiCodePoints.stableID(EmojiCodePoints.values(in: entry.emoji)),
                  entry.canonicalName.isEmpty == false,
                  entry.canonicalAlias.isEmpty == false,
                  EmojiTermNormalizer.normalize(entry.canonicalAlias) == entry.canonicalAlias,
                  entry.skinToneVariants.first == entry.emoji,
                  Set(entry.skinToneVariants).count == entry.skinToneVariants.count,
                  entry.alternateAliases.allSatisfy({
                      $0.isEmpty == false && EmojiTermNormalizer.normalize($0) == $0
                  }),
                  entry.tags.allSatisfy({
                      $0.isEmpty == false && EmojiTermNormalizer.normalize($0) == $0
                  })
            else {
                throw EmojiDataGeneratorError.invalidEntry(entry.id.rawValue)
            }

            for alias in [entry.canonicalAlias] + entry.alternateAliases {
                if let existingOwner = aliasOwners[alias], existingOwner != entry.id {
                    throw EmojiDataGeneratorError.duplicateAlias(
                        alias: alias,
                        firstID: existingOwner.rawValue,
                        secondID: entry.id.rawValue
                    )
                }
                aliasOwners[alias] = entry.id
            }

            for variant in entry.skinToneVariants.dropFirst() {
                let sequenceKey = EmojiCodePoints.codePointKey(EmojiCodePoints.values(in: variant))
                guard officialSkinToneSequenceKeys.contains(sequenceKey) else {
                    throw EmojiDataGeneratorError.unofficialSkinToneVariant(
                        emojiID: entry.id.rawValue,
                        variant: variant
                    )
                }
            }
        }

        guard sortOrders == Set(dataset.entries.indices) else {
            throw EmojiDataGeneratorError.invalidEntry("sort-order")
        }
    }
}
