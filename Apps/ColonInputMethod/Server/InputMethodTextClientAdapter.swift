import AppKit
import ColonTokenization
import ColonPickerModels
import InputMethodKit

final class InputMethodTextClientAdapter: TextCommitClient {
    private let client: any IMKTextInput

    init?(client: Any) {
        guard let textInputClient = client as? any IMKTextInput else {
            return nil
        }
        self.client = textInputClient
    }

    var bundleIdentifier: String? {
        client.bundleIdentifier()
    }

    var selectedRange: NSRange {
        client.selectedRange()
    }

    func substring(in proposedRange: NSRange) -> TextClientSubstring? {
        var actualRange = NSRange(location: NSNotFound, length: 0)
        guard let substring = client.string(
            from: proposedRange,
            actualRange: &actualRange
        ) else {
            return nil
        }
        return TextClientSubstring(
            text: substring,
            actualRange: actualRange
        )
    }

    @MainActor
    func caretRect() -> NSRect? {
        // IMK explicitly provides this API for candidate-window placement.
        // No marked-text session is used, so index zero means current selection.
        var lineRect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        if let rect = validatedCaretRect(lineRect) { return rect }
        var actualRange = NSRange(location: NSNotFound, length: 0)
        let rect = client.firstRect(
            forCharacterRange: selectedRange,
            actualRange: &actualRange
        )
        guard actualRange.location != NSNotFound else { return nil }
        return validatedCaretRect(rect)
    }

    @MainActor
    private func validatedCaretRect(_ rect: NSRect) -> NSRect? {
        let screens = NSScreen.screens.map {
            PanelRect(x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width, height: $0.frame.height)
        }
        guard let anchor = CaretAnchorResolver.validated(
            PanelRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height),
            screens: screens
        ) else { return nil }
        return NSRect(x: anchor.minX, y: anchor.minY, width: anchor.size.width, height: anchor.size.height)
    }

    func replaceText(with text: String, replacementRange: NSRange) {
        client.insertText(text, replacementRange: replacementRange)
    }
}
