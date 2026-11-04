import CryptoKit
import Foundation

enum EmojiCodePoints {
    static let variationSelector16: UInt32 = 0xFE0F

    static func values(in string: String) -> [UInt32] {
        string.unicodeScalars.map(\.value)
    }

    static func string(from values: [UInt32]) throws -> String {
        var scalars = String.UnicodeScalarView()
        for value in values {
            guard let scalar = Unicode.Scalar(value) else {
                throw EmojiDataGeneratorError.invalidEntry(codePointKey(values))
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    static func stableID(_ values: [UInt32]) -> String {
        codePointKey(values.filter { $0 != variationSelector16 })
    }

    static func codePointKey(_ values: [UInt32]) -> String {
        values.map { String($0, radix: 16, uppercase: false) }.joined(separator: "-")
    }

    static func normalizedEmojiKey(_ emoji: String) -> String {
        stableID(values(in: emoji))
    }

    static func containsSkinToneModifier(_ values: [UInt32]) -> Bool {
        values.contains(where: { (0x1F3FB...0x1F3FF).contains($0) })
    }

    static func removingSkinToneModifiers(_ values: [UInt32]) -> [UInt32] {
        values.filter { !(0x1F3FB...0x1F3FF).contains($0) }
    }
}

public enum EmojiTermNormalizer {
    public static func normalize(_ source: String) -> String {
        let folded = source.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )

        var result = ""
        var lastWasUnderscore = false

        for scalar in folded.unicodeScalars {
            let isAllowed = switch scalar.value {
            case 48...57, 97...122, 43, 45:
                true
            default:
                false
            }

            if isAllowed {
                result.unicodeScalars.append(scalar)
                lastWasUnderscore = false
            } else if scalar.value == 95 || CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar.isASCII {
                if result.isEmpty == false, lastWasUnderscore == false {
                    result.append("_")
                    lastWasUnderscore = true
                }
            }
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

enum EmojiDataHashing {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

func stableUnique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0).inserted }
}
