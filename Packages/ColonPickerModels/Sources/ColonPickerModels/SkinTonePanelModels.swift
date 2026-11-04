public enum SkinToneCycle {
    public static func nextIndex(after currentIndex: Int, count: Int) -> Int {
        guard count > 0 else {
            return 0
        }
        return (max(0, currentIndex) + 1) % count
    }
}

public struct SkinTonePanelItem: Identifiable, Equatable, Sendable {
    public let id: Int
    public let emoji: String
    public let accessibilityLabel: String
    public let isSelected: Bool

    public init(id: Int, emoji: String, accessibilityLabel: String, isSelected: Bool) {
        self.id = id
        self.emoji = emoji
        self.accessibilityLabel = accessibilityLabel
        self.isSelected = isSelected
    }
}

public struct SkinTonePanelViewModel: Equatable, Sendable {
    public let items: [SkinTonePanelItem]
    public let appearance: CandidatePanelAppearance
    public let accessibility: CandidatePanelAccessibility

    public init(
        selection: SkinToneSelection,
        appearance: CandidatePanelAppearance,
        accessibility: CandidatePanelAccessibility
    ) {
        items = selection.variants.enumerated().map { index, emoji in
            SkinTonePanelItem(
                id: index,
                emoji: emoji,
                accessibilityLabel: Self.accessibilityLabel(for: emoji),
                isSelected: index == selection.selectedIndex
            )
        }
        self.appearance = appearance
        self.accessibility = accessibility
    }

    public var snapshotDescription: String {
        let header = "appearance=\(appearance.rawValue)|increaseContrast=\(accessibility.increaseContrast)"
        return ([header] + items.map {
            "\($0.isSelected ? "selected" : "normal")|\($0.emoji)|\($0.accessibilityLabel)"
        }).joined(separator: "\n")
    }

    public static func accessibilityLabel(for emoji: String) -> String {
        let toneNames = emoji.unicodeScalars.compactMap { scalar -> String? in
            switch scalar.value {
            case 0x1F3FB: "light skin tone"
            case 0x1F3FC: "medium-light skin tone"
            case 0x1F3FD: "medium skin tone"
            case 0x1F3FE: "medium-dark skin tone"
            case 0x1F3FF: "dark skin tone"
            default: nil
            }
        }
        return toneNames.isEmpty ? "default skin tone" : toneNames.joined(separator: ", ")
    }
}
