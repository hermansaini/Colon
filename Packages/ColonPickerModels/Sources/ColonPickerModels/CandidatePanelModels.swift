import ColonModels

public enum CandidatePanelAppearance: String, Equatable, Sendable {
    case system
    case light
    case dark
}

public struct CandidatePanelAccessibility: Equatable, Sendable {
    public let reduceMotion: Bool
    public let increaseContrast: Bool

    public init(reduceMotion: Bool, increaseContrast: Bool) {
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
    }
}

public struct CandidatePanelMetrics: Equatable, Sendable {
    public let width: Double
    public let rowHeight: Double
    public let horizontalPadding: Double

    public static func metrics(for size: PickerSize) -> Self {
        switch size {
        case .compact:
            Self(width: 280, rowHeight: 32, horizontalPadding: 10)
        case .standard:
            Self(width: 320, rowHeight: 36, horizontalPadding: 10)
        case .large:
            Self(width: 390, rowHeight: 58, horizontalPadding: 14)
        }
    }
}

public struct CandidatePanelRow: Identifiable, Equatable, Sendable {
    public let id: EmojiID
    public let emoji: String
    public let canonicalName: String
    public let canonicalAlias: String
    public let matchingHint: String?
    public let isSelected: Bool

    public init(
        id: EmojiID,
        emoji: String,
        canonicalName: String,
        canonicalAlias: String,
        matchingHint: String?,
        isSelected: Bool
    ) {
        self.id = id
        self.emoji = emoji
        self.canonicalName = canonicalName
        self.canonicalAlias = canonicalAlias
        self.matchingHint = matchingHint
        self.isSelected = isSelected
    }
}

public struct CandidatePanelViewModel: Equatable, Sendable {
    public let rows: [CandidatePanelRow]
    public let visibleRowCount: Int
    public let metrics: CandidatePanelMetrics
    public let appearance: CandidatePanelAppearance
    public let accessibility: CandidatePanelAccessibility
    public let correctionMessage: String?

    public var selectedRowID: EmojiID? {
        rows.first(where: \.isSelected)?.id
    }

    public var contentHeight: Double {
        Double(min(visibleRowCount, max(1, rows.count))) * metrics.rowHeight
            + (correctionMessage == nil ? 0 : 28)
    }

    public init(
        selection: CandidateSelection,
        visibleRowCount: Int,
        size: PickerSize,
        appearance: CandidatePanelAppearance,
        accessibility: CandidatePanelAccessibility,
        correctionMessage: String? = nil
    ) {
        rows = selection.candidates.enumerated().map { index, candidate in
            let hint = candidate.matchedTerm == candidate.entry.canonicalAlias
                ? nil
                : candidate.matchedTerm
            return CandidatePanelRow(
                id: candidate.id,
                emoji: candidate.renderedEmoji,
                canonicalName: candidate.entry.canonicalName,
                canonicalAlias: candidate.entry.canonicalAlias,
                matchingHint: hint,
                isSelected: correctionMessage == nil && index == selection.selectedIndex
            )
        }
        self.visibleRowCount = min(max(1, visibleRowCount), 12)
        metrics = .metrics(for: size)
        self.appearance = appearance
        self.accessibility = accessibility
        self.correctionMessage = correctionMessage
    }

    public var snapshotDescription: String {
        let header = [
            "appearance=\(appearance.rawValue)",
            "rows=\(visibleRowCount)",
            "width=\(Int(metrics.width))",
            "rowHeight=\(Int(metrics.rowHeight))",
            "reduceMotion=\(accessibility.reduceMotion)",
            "increaseContrast=\(accessibility.increaseContrast)",
        ].joined(separator: "|")
        let rowDescriptions = rows.map { row in
            let selection = row.isSelected ? "selected" : "normal"
            let hint = row.matchingHint ?? "none"
            return "\(selection)|\(row.emoji)|:\(row.canonicalAlias)|\(row.canonicalName)|hint=\(hint)"
        }
        return ([header] + rowDescriptions).joined(separator: "\n")
    }
}

public struct CandidatePanelScrollTarget: Equatable, Sendable {
    public let rowID: EmojiID?
    public let revision: UInt

    public init(rowID: EmojiID?, revision: UInt) {
        self.rowID = rowID
        self.revision = revision
    }
}

public struct CandidatePanelPresentationState: Equatable, Sendable {
    public private(set) var model: CandidatePanelViewModel
    public private(set) var scrollTarget: CandidatePanelScrollTarget

    public init(model: CandidatePanelViewModel) {
        self.model = model
        scrollTarget = CandidatePanelScrollTarget(
            rowID: model.selectedRowID,
            revision: 0
        )
    }

    public mutating func update(model: CandidatePanelViewModel) {
        self.model = model
        scrollTarget = CandidatePanelScrollTarget(
            rowID: model.selectedRowID,
            revision: scrollTarget.revision &+ 1
        )
    }
}

public struct PanelPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct PanelSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct PanelRect: Equatable, Sendable {
    public let origin: PanelPoint
    public let size: PanelSize

    public init(x: Double, y: Double, width: Double, height: Double) {
        origin = PanelPoint(x: x, y: y)
        size = PanelSize(width: width, height: height)
    }

    public var minX: Double { origin.x }
    public var maxX: Double { origin.x + size.width }
    public var minY: Double { origin.y }
    public var maxY: Double { origin.y + size.height }
}

public enum CandidatePanelPositioner {
    public static func frame(
        anchor: PanelRect,
        panelSize: PanelSize,
        visibleScreen: PanelRect,
        gap: Double = 6
    ) -> PanelRect {
        let maximumX = max(visibleScreen.minX, visibleScreen.maxX - panelSize.width)
        let x = min(max(anchor.minX, visibleScreen.minX), maximumX)
        let belowY = anchor.minY - gap - panelSize.height
        let aboveY = anchor.maxY + gap
        let preferredY = aboveY + panelSize.height <= visibleScreen.maxY ? aboveY : belowY
        let maximumY = max(visibleScreen.minY, visibleScreen.maxY - panelSize.height)
        let y = min(max(preferredY, visibleScreen.minY), maximumY)
        return PanelRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }
}

/// IMK and AppKit return screen-space rectangles. Reject missing/off-screen
/// geometry rather than placing a detached picker at a screen origin.
public enum CaretAnchorResolver {
    public static func validated(_ rect: PanelRect, screens: [PanelRect]) -> PanelRect? {
        guard [rect.minX, rect.minY, rect.size.width, rect.size.height, rect.maxX, rect.maxY]
            .allSatisfy(\.isFinite), rect.size.height != 0 else {
            return nil
        }
        let normalized = PanelRect(
            x: min(rect.minX, rect.maxX), y: min(rect.minY, rect.maxY),
            width: max(1, abs(rect.size.width)), height: abs(rect.size.height)
        )
        guard screens.contains(where: {
            normalized.minX < $0.maxX && normalized.maxX > $0.minX
                && normalized.minY < $0.maxY && normalized.maxY > $0.minY
                && normalized.size.height <= $0.size.height
                && normalized.size.width <= $0.size.width
        }) else { return nil }
        return normalized
    }
}

public struct CandidatePanelSessionGate: Equatable, Sendable {
    public private(set) var activeToken: String?

    public init(activeToken: String? = nil) {
        self.activeToken = activeToken
    }

    public mutating func begin(token: String) {
        activeToken = token
    }

    public mutating func invalidate() {
        activeToken = nil
    }

    public func accepts(token: String) -> Bool {
        activeToken == token
    }
}
