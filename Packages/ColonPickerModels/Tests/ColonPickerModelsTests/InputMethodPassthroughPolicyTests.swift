import XCTest
@testable import ColonPickerModels

final class InputMethodPassthroughPolicyTests: XCTestCase {
    func testLifecycleTransitionsAndNeverConsumesInput() {
        var policy = InputMethodPassthroughPolicy()
        XCTAssertEqual(policy.state, .created)
        XCTAssertFalse(policy.shouldConsumeKeyEvent())
        XCTAssertFalse(policy.shouldRespondToMouseActivation(isRuntimeReady: true))
        XCTAssertFalse(policy.shouldScheduleHostRefresh(
            isKeyDown: true,
            keyCode: 0,
            hasActiveToken: false,
            characters: ":",
            hasSystemShortcutModifier: false
        ))

        policy.activate()
        XCTAssertEqual(policy.state, .active)
        XCTAssertFalse(policy.shouldConsumeKeyEvent())
        XCTAssertFalse(policy.shouldRespondToMouseActivation(isRuntimeReady: false))
        XCTAssertTrue(policy.shouldRespondToMouseActivation(isRuntimeReady: true))
        XCTAssertTrue(policy.shouldScheduleHostRefresh(
            isKeyDown: true,
            keyCode: 0,
            hasActiveToken: false,
            characters: ":",
            hasSystemShortcutModifier: false
        ))
        XCTAssertFalse(policy.shouldScheduleHostRefresh(
            isKeyDown: true,
            keyCode: 0,
            hasActiveToken: false,
            characters: "a",
            hasSystemShortcutModifier: false
        ))
        XCTAssertFalse(policy.shouldScheduleHostRefresh(
            isKeyDown: true,
            keyCode: 0,
            hasActiveToken: false,
            characters: ":",
            hasSystemShortcutModifier: true
        ))
        XCTAssertTrue(policy.shouldScheduleHostRefresh(
            isKeyDown: true,
            keyCode: 0,
            hasActiveToken: true,
            characters: "a",
            hasSystemShortcutModifier: false
        ))
        XCTAssertFalse(policy.shouldScheduleHostRefresh(
            isKeyDown: false,
            keyCode: 0,
            hasActiveToken: true,
            characters: "a",
            hasSystemShortcutModifier: false
        ))

        for keyCode: UInt16 in [48, 51, 117, 123, 124, 125, 126] {
            XCTAssertTrue(policy.shouldScheduleHostRefresh(
                isKeyDown: true,
                keyCode: keyCode,
                hasActiveToken: false,
                characters: nil,
                hasSystemShortcutModifier: false
            ))
        }
        XCTAssertFalse(policy.shouldScheduleHostRefresh(
            isKeyDown: true,
            keyCode: 0,
            hasActiveToken: false,
            characters: "b",
            hasSystemShortcutModifier: false
        ))

        for keyCode: UInt16 in [36, 48, 53, 76, 125, 126] {
            XCTAssertTrue(policy.shouldHandlePickerKeyEvent(
                isKeyDown: true,
                keyCode: keyCode,
                hasSystemShortcutModifier: false,
                hasShiftModifier: false,
                hasPickerState: true
            ))
            XCTAssertFalse(policy.shouldHandlePickerKeyEvent(
                isKeyDown: true,
                keyCode: keyCode,
                hasSystemShortcutModifier: true,
                hasShiftModifier: false,
                hasPickerState: true
            ))
            XCTAssertFalse(policy.shouldHandlePickerKeyEvent(
                isKeyDown: true,
                keyCode: keyCode,
                hasSystemShortcutModifier: false,
                hasShiftModifier: true,
                hasPickerState: true
            ))
            XCTAssertFalse(policy.shouldHandlePickerKeyEvent(
                isKeyDown: true,
                keyCode: keyCode,
                hasSystemShortcutModifier: false,
                hasShiftModifier: false,
                hasPickerState: false
            ))
        }
        XCTAssertFalse(policy.shouldHandlePickerKeyEvent(
            isKeyDown: false,
            keyCode: 125,
            hasSystemShortcutModifier: false,
            hasShiftModifier: false,
            hasPickerState: true
        ))

        policy.deactivate()
        XCTAssertEqual(policy.state, .inactive)
        XCTAssertFalse(policy.shouldConsumeKeyEvent())
        XCTAssertFalse(policy.shouldRespondToMouseActivation(isRuntimeReady: true))
        XCTAssertFalse(policy.shouldScheduleHostRefresh(
            isKeyDown: true,
            keyCode: 0,
            hasActiveToken: true,
            characters: "a",
            hasSystemShortcutModifier: false
        ))
    }
}
