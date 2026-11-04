import Foundation

public struct TextClientSubstring: Equatable, Sendable {
    public let text: String
    public let actualRange: NSRange

    public init(text: String, actualRange: NSRange) {
        self.text = text
        self.actualRange = actualRange
    }
}

public protocol MinimalTextClient: AnyObject {
    var selectedRange: NSRange { get }
    func substring(in proposedRange: NSRange) -> TextClientSubstring?
}

public struct MinimalTextContext: Equatable, Sendable {
    public let snapshot: TextContextSnapshot
    public let documentContextRange: NSRange

    public init(snapshot: TextContextSnapshot, documentContextRange: NSRange) {
        self.snapshot = snapshot
        self.documentContextRange = documentContextRange
    }

    public func hasKnownTokenStart(at localLocation: Int) -> Bool {
        guard localLocation >= 0 else {
            return false
        }
        return localLocation > 0 || documentContextRange.location == 0
    }

    public func documentRange(for localRange: NSRange) -> NSRange? {
        guard documentContextRange.location >= 0,
              documentContextRange.location != NSNotFound,
              documentContextRange.length >= 0,
              documentContextRange.length < NSNotFound - documentContextRange.location,
              localRange.location >= 0,
              localRange.length >= 0,
              localRange.location <= documentContextRange.length,
              localRange.length <= documentContextRange.length - localRange.location,
              localRange.location <= Int.max - documentContextRange.location
        else {
            return nil
        }
        return NSRange(
            location: documentContextRange.location + localRange.location,
            length: localRange.length
        )
    }
}

public struct MinimalTextContextReader: Sendable {
    public let maximumUTF16Length: Int

    public init(maximumUTF16Length: Int = 256) {
        precondition(maximumUTF16Length > 0)
        self.maximumUTF16Length = maximumUTF16Length
    }

    public func read(from client: any MinimalTextClient) -> MinimalTextContext? {
        let selectedRange = client.selectedRange
        guard selectedRange.location >= 0,
              selectedRange.location != NSNotFound,
              selectedRange.length == 0
        else {
            return nil
        }

        let contextLength = min(maximumUTF16Length, selectedRange.location)
        let contextStart = selectedRange.location - contextLength
        let proposedRange = NSRange(
            location: contextStart,
            length: contextLength
        )
        guard let substring = client.substring(in: proposedRange),
              substring.actualRange.location >= 0,
              substring.actualRange.length >= 0,
              substring.actualRange.location >= proposedRange.location,
              substring.actualRange.location <= selectedRange.location,
              substring.actualRange.length <= proposedRange.length,
              substring.actualRange.length <= maximumUTF16Length,
              substring.actualRange.length == selectedRange.location - substring.actualRange.location,
              (substring.text as NSString).length == substring.actualRange.length
        else {
            return nil
        }

        return MinimalTextContext(
            snapshot: TextContextSnapshot(textBeforeCaret: substring.text),
            documentContextRange: substring.actualRange
        )
    }
}
