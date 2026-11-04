import ColonModels
import ColonTokenization

public struct EmojiSearchEngine: Sendable {
    private enum TermRole: Int, Hashable, Sendable {
        case canonicalAlias
        case alternateAlias
        case tag
    }

    private struct IndexedTerm: Hashable, Sendable {
        let entryIndex: Int
        let term: String
        let role: TermRole
    }

    private struct TermKey: Hashable {
        let entryIndex: Int
        let term: String
        let role: TermRole
    }

    private let entries: [EmojiEntry]
    private let exactIndex: [String: [IndexedTerm]]
    private let allTerms: [IndexedTerm]
    private let renderedEmojiByID: [EmojiID: String]

    public init(
        dataset: EmojiDataset,
        customTags: CustomTagsSnapshot = .defaults,
        skinTonePreferences: SkinTonePreferencesSnapshot = .defaults
    ) {
        entries = dataset.entries

        let entryIndexByID = Dictionary(
            uniqueKeysWithValues: dataset.entries.enumerated().map { ($0.element.id, $0.offset) }
        )
        var terms: [IndexedTerm] = []
        var termKeys: Set<TermKey> = []

        func appendTerm(_ term: String, role: TermRole, entryIndex: Int) {
            guard term.isEmpty == false,
                  let normalizedTerm = EmojiQueryNormalizer.normalize(term)
            else {
                return
            }

            let key = TermKey(entryIndex: entryIndex, term: normalizedTerm, role: role)
            guard termKeys.insert(key).inserted else {
                return
            }
            terms.append(IndexedTerm(entryIndex: entryIndex, term: normalizedTerm, role: role))
        }

        for (entryIndex, entry) in dataset.entries.enumerated() {
            appendTerm(entry.canonicalAlias, role: .canonicalAlias, entryIndex: entryIndex)
            for alias in entry.alternateAliases {
                appendTerm(alias, role: .alternateAlias, entryIndex: entryIndex)
            }
            for tag in entry.tags {
                appendTerm(tag, role: .tag, entryIndex: entryIndex)
            }
        }

        let sortedCustomTags = customTags.records.sorted {
            if $0.emojiID != $1.emojiID {
                return $0.emojiID.rawValue < $1.emojiID.rawValue
            }
            if $0.normalizedTag != $1.normalizedTag {
                return $0.normalizedTag < $1.normalizedTag
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        for record in sortedCustomTags {
            guard let entryIndex = entryIndexByID[record.emojiID] else {
                continue
            }
            appendTerm(record.normalizedTag, role: .tag, entryIndex: entryIndex)
        }

        // Terms that share a prefix are contiguous, so a query can find its
        // prefix matches with a binary search instead of scanning every term
        // that starts with the same first character.
        terms.sort {
            if $0.term != $1.term {
                return $0.term < $1.term
            }
            if $0.role != $1.role {
                return $0.role.rawValue < $1.role.rawValue
            }
            return $0.entryIndex < $1.entryIndex
        }
        allTerms = terms

        var exactIndex: [String: [IndexedTerm]] = [:]
        for term in terms {
            exactIndex[term.term, default: []].append(term)
        }
        self.exactIndex = exactIndex
        renderedEmojiByID = Self.makeRenderedEmojiLookup(
            entries: dataset.entries,
            preferences: skinTonePreferences.preferences
        )
    }

    public func search(query: String, maximumResultCount: Int) -> [EmojiCandidate] {
        guard maximumResultCount > 0,
              query.isEmpty == false,
              let normalizedQuery = EmojiQueryNormalizer.normalize(query)
        else {
            return []
        }

        var bestCandidateByID: [EmojiID: EmojiCandidate] = [:]

        for term in exactIndex[normalizedQuery, default: []] {
            mergeCandidate(for: term, query: normalizedQuery, into: &bestCandidateByID)
        }

        var prefixTermIndex = firstTermIndex(notLessThan: normalizedQuery)
        while prefixTermIndex < allTerms.count {
            let term = allTerms[prefixTermIndex]
            guard term.term.hasPrefix(normalizedQuery) else {
                break
            }
            if term.term != normalizedQuery {
                mergeCandidate(for: term, query: normalizedQuery, into: &bestCandidateByID)
            }
            prefixTermIndex += 1
        }

        // Every prefix match outranks every contains match, even after the
        // score's length penalty. Once the result limit is filled with distinct
        // exact/prefix candidates, substring results cannot affect the output.
        if bestCandidateByID.count < maximumResultCount {
            for term in allTerms
                where term.term.hasPrefix(normalizedQuery) == false && term.term.contains(normalizedQuery)
            {
                mergeCandidate(for: term, query: normalizedQuery, into: &bestCandidateByID)
            }
        }

        return bestCandidateByID.values.sorted(by: Self.candidatePrecedes).prefix(maximumResultCount).map { $0 }
    }

    private func firstTermIndex(notLessThan query: String) -> Int {
        var lowerBound = 0
        var upperBound = allTerms.count

        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if allTerms[middle].term < query {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func mergeCandidate(
        for term: IndexedTerm,
        query: String,
        into bestCandidateByID: inout [EmojiID: EmojiCandidate]
    ) {
        let entry = entries[term.entryIndex]
        let matchKind = Self.matchKind(for: term, query: query)
        let candidate = EmojiCandidate(
            id: entry.id,
            entry: entry,
            renderedEmoji: renderedEmojiByID[entry.id] ?? entry.emoji,
            matchedTerm: term.term,
            matchKind: matchKind,
            score: Self.score(for: matchKind, term: term.term, query: query)
        )

        if let existing = bestCandidateByID[entry.id],
           Self.candidatePrecedes(existing, candidate) {
            return
        }
        bestCandidateByID[entry.id] = candidate
    }

    private static func matchKind(for term: IndexedTerm, query: String) -> MatchKind {
        if term.term == query {
            switch term.role {
            case .canonicalAlias:
                return .exactCanonical
            case .alternateAlias:
                return .exactAlternate
            case .tag:
                return .tagPrefix
            }
        }

        if term.term.hasPrefix(query) {
            switch term.role {
            case .canonicalAlias:
                return .canonicalPrefix
            case .alternateAlias:
                return .alternatePrefix
            case .tag:
                return .tagPrefix
            }
        }

        switch term.role {
        case .canonicalAlias, .alternateAlias:
            return .aliasContains
        case .tag:
            return .tagContains
        }
    }

    private static func score(for kind: MatchKind, term: String, query: String) -> Int {
        let bandTop: Int
        switch kind {
        case .exactCanonical:
            bandTop = 10_000
        case .exactAlternate:
            bandTop = 9_000
        case .canonicalPrefix:
            bandTop = 8_000
        case .alternatePrefix:
            bandTop = 7_000
        case .tagPrefix:
            bandTop = 6_000
        case .aliasContains:
            bandTop = 5_000
        case .tagContains:
            bandTop = 4_000
        }

        guard kind != .exactCanonical, kind != .exactAlternate else {
            return bandTop
        }

        let lengthDistance = max(0, term.utf8.count - query.utf8.count)
        let locationDistance: Int
        if kind == .aliasContains || kind == .tagContains,
           let range = term.range(of: query) {
            locationDistance = term[..<range.lowerBound].utf8.count * 16
        } else {
            locationDistance = 0
        }
        return bandTop - min(999, lengthDistance + locationDistance)
    }

    private static func candidatePrecedes(_ left: EmojiCandidate, _ right: EmojiCandidate) -> Bool {
        if left.score != right.score {
            return left.score > right.score
        }
        if left.matchKind.rawValue != right.matchKind.rawValue {
            return left.matchKind.rawValue < right.matchKind.rawValue
        }
        if left.matchedTerm.count != right.matchedTerm.count {
            return left.matchedTerm.count < right.matchedTerm.count
        }
        if left.matchedTerm != right.matchedTerm {
            return left.matchedTerm < right.matchedTerm
        }
        if left.entry.sortOrder != right.entry.sortOrder {
            return left.entry.sortOrder < right.entry.sortOrder
        }
        if left.entry.canonicalAlias != right.entry.canonicalAlias {
            return left.entry.canonicalAlias < right.entry.canonicalAlias
        }
        return left.id.rawValue < right.id.rawValue
    }

    private static func makeRenderedEmojiLookup(
        entries: [EmojiEntry],
        preferences: [SkinTonePreference]
    ) -> [EmojiID: String] {
        var latestPreferenceByID: [EmojiID: SkinTonePreference] = [:]
        for preference in preferences {
            guard let existing = latestPreferenceByID[preference.emojiID] else {
                latestPreferenceByID[preference.emojiID] = preference
                continue
            }
            if preference.updatedAt > existing.updatedAt
                || (preference.updatedAt == existing.updatedAt
                    && preference.selectedVariant < existing.selectedVariant) {
                latestPreferenceByID[preference.emojiID] = preference
            }
        }

        return Dictionary(uniqueKeysWithValues: entries.map { entry in
            let preferredVariant = latestPreferenceByID[entry.id]?.selectedVariant
            let renderedEmoji = preferredVariant.flatMap {
                entry.skinToneVariants.contains($0) ? $0 : nil
            } ?? entry.emoji
            return (entry.id, renderedEmoji)
        })
    }
}
