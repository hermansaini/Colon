public enum InputMethodSessionState: Equatable, Sendable {
    case created
    case active
    case inactive
}

public struct InputMethodPassthroughPolicy: Equatable, Sendable {
    public private(set) var state: InputMethodSessionState = .created

    public init() {}

    public mutating func activate() {
        state = .active
    }

    public mutating func deactivate() {
        state = .inactive
    }

    public func shouldConsumeKeyEvent() -> Bool {
        false
    }

    public func shouldRespondToMouseActivation(isRuntimeReady: Bool) -> Bool {
        state == .active && isRuntimeReady
    }

    public func shouldScheduleHostRefresh(
        isKeyDown: Bool,
        keyCode: UInt16,
        hasActiveToken: Bool,
        characters: String?,
        hasSystemShortcutModifier: Bool
    ) -> Bool {
        guard state == .active, isKeyDown else {
            return false
        }
        return hasActiveToken
            || (hasSystemShortcutModifier == false && characters == ":")
            || Self.mayChangeCaretOrExposeToken(keyCode: keyCode)
    }

    public func shouldHandlePickerKeyEvent(
        isKeyDown: Bool,
        keyCode: UInt16,
        hasSystemShortcutModifier: Bool,
        hasShiftModifier: Bool,
        hasPickerState: Bool
    ) -> Bool {
        guard state == .active,
              isKeyDown,
              hasSystemShortcutModifier == false,
              hasShiftModifier == false,
              hasPickerState
        else {
            return false
        }
        switch keyCode {
        case 36, 48, 53, 76, 125, 126:
            return true
        default:
            return false
        }
    }

    private static func mayChangeCaretOrExposeToken(keyCode: UInt16) -> Bool {
        switch keyCode {
        case 48, 51, 115, 116, 117, 119, 121, 123, 124, 125, 126:
            true
        default:
            false
        }
    }
}
