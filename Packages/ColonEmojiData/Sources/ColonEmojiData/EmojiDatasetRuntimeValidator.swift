import ColonModels

enum EmojiDatasetRuntimeValidator {
    static func validate(_ dataset: EmojiDataset) throws {
        guard dataset.schemaVersion == EmojiDataset.currentSchemaVersion else {
            throw EmojiDataError.unsupportedSchema(dataset.schemaVersion)
        }
        guard dataset.entries.isEmpty == false else {
            throw EmojiDataError.emptyDataset
        }
        guard dataset.metadata.unicodeEmojiVersion.isEmpty == false,
              dataset.metadata.cldrVersion.isEmpty == false,
              dataset.metadata.gemojiCommit.isEmpty == false,
              dataset.metadata.generatedAt.isEmpty == false
        else {
            throw EmojiDataError.invalidEntry("metadata")
        }

        var ids: Set<EmojiID> = []
        var sortOrders: Set<Int> = []
        var aliasOwners: [String: EmojiID] = [:]

        for entry in dataset.entries {
            guard ids.insert(entry.id).inserted else {
                throw EmojiDataError.duplicateEmojiID(entry.id.rawValue)
            }
            guard sortOrders.insert(entry.sortOrder).inserted,
                  entry.id.rawValue == stableID(for: entry.emoji),
                  entry.canonicalName.isEmpty == false,
                  isNormalized(entry.canonicalAlias),
                  entry.alternateAliases.allSatisfy(isNormalized),
                  entry.tags.allSatisfy(isNormalized),
                  entry.skinToneVariants.first == entry.emoji,
                  Set(entry.skinToneVariants).count == entry.skinToneVariants.count
            else {
                throw EmojiDataError.invalidEntry(entry.id.rawValue)
            }

            for alias in [entry.canonicalAlias] + entry.alternateAliases {
                if let owner = aliasOwners[alias], owner != entry.id {
                    throw EmojiDataError.duplicateAlias(alias)
                }
                aliasOwners[alias] = entry.id
            }

            for variant in entry.skinToneVariants.dropFirst() {
                guard variant.unicodeScalars.contains(where: {
                    (0x1F3FB...0x1F3FF).contains($0.value)
                }) else {
                    throw EmojiDataError.invalidSkinToneVariant(entry.id.rawValue)
                }
            }
        }

        guard sortOrders == Set(dataset.entries.indices) else {
            throw EmojiDataError.invalidEntry("sort-order")
        }
    }

    private static func stableID(for emoji: String) -> String {
        emoji.unicodeScalars
            .map(\.value)
            .filter { $0 != 0xFE0F }
            .map { String($0, radix: 16, uppercase: false) }
            .joined(separator: "-")
    }

    private static func isNormalized(_ value: String) -> Bool {
        guard value.isEmpty == false,
              value.hasPrefix("_") == false,
              value.hasSuffix("_") == false,
              value.contains("__") == false
        else {
            return false
        }

        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 97...122, 43, 45, 95:
                true
            default:
                false
            }
        }
    }
}
