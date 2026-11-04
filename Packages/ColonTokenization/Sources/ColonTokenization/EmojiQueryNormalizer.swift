public enum EmojiQueryNormalizer {
    public static func normalize(_ query: String) -> String? {
        guard query.unicodeScalars.allSatisfy(isAllowed) else {
            return nil
        }

        return query.lowercased()
    }

    public static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 43, 45, 48...57, 65...90, 95, 97...122:
            true
        default:
            false
        }
    }
}
