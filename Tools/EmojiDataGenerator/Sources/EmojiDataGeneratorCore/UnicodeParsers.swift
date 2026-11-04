import Foundation

enum UnicodeEmojiTestParser {
    static func parse(_ data: Data) throws -> UnicodeEmojiTestData {
        let content = String(decoding: data, as: UTF8.self)
        var version: String?
        var category: String?
        var records: [UnicodeEmojiRecord] = []

        for (lineIndex, rawLine) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("# Version:") {
                version = line.replacingOccurrences(of: "# Version:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            if line.hasPrefix("# group:") {
                category = line.replacingOccurrences(of: "# group:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            guard line.isEmpty == false, line.hasPrefix("#") == false else {
                continue
            }

            let semicolonParts = line.split(separator: ";", maxSplits: 1)
            guard semicolonParts.count == 2 else {
                throw EmojiDataGeneratorError.malformedUnicodeLine(lineIndex + 1)
            }

            let remainder = semicolonParts[1].split(separator: "#", maxSplits: 1)
            guard remainder.count == 2,
                  remainder[0].trimmingCharacters(in: .whitespaces) == "fully-qualified",
                  let category
            else {
                continue
            }

            let codePoints = try parseCodePoints(String(semicolonParts[0]), line: lineIndex + 1)
            let commentParts = remainder[1].trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard commentParts.count == 3 else {
                throw EmojiDataGeneratorError.malformedUnicodeLine(lineIndex + 1)
            }

            records.append(
                UnicodeEmojiRecord(
                    codePoints: codePoints,
                    emoji: try EmojiCodePoints.string(from: codePoints),
                    name: String(commentParts[2]),
                    category: category,
                    sourceOrder: records.count
                )
            )
        }

        guard let version else {
            throw EmojiDataGeneratorError.malformedUnicodeLine(1)
        }

        return UnicodeEmojiTestData(version: version, records: records)
    }

    private static func parseCodePoints(_ value: String, line: Int) throws -> [UInt32] {
        try value.split(whereSeparator: \.isWhitespace).map { token in
            guard let codePoint = UInt32(token, radix: 16) else {
                throw EmojiDataGeneratorError.malformedUnicodeLine(line)
            }
            return codePoint
        }
    }
}

enum UnicodeEmojiSequenceParser {
    static func officialSkinToneSequenceKeys(from sourceFiles: [Data]) throws -> Set<String> {
        var sequences: Set<String> = []

        for data in sourceFiles {
            let content = String(decoding: data, as: UTF8.self)
            for (lineIndex, rawLine) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard line.isEmpty == false, line.hasPrefix("#") == false else {
                    continue
                }

                let firstField = line.split(separator: ";", maxSplits: 1)[0]
                guard firstField.contains("..") == false else {
                    continue
                }

                let codePoints = try firstField.split(whereSeparator: \.isWhitespace).map { token in
                    guard let codePoint = UInt32(token, radix: 16) else {
                        throw EmojiDataGeneratorError.malformedUnicodeLine(lineIndex + 1)
                    }
                    return codePoint
                }

                if EmojiCodePoints.containsSkinToneModifier(codePoints) {
                    sequences.insert(EmojiCodePoints.codePointKey(codePoints))
                }
            }
        }

        return sequences
    }
}
