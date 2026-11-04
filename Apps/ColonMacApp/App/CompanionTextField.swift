import AppKit
import SwiftUI

/// Only this field's editor handles picker commands. No application-wide key monitor.
@MainActor
struct CompanionTextField: NSViewRepresentable {
    @ObservedObject var viewModel: BuildInformationViewModel

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: viewModel.tokenText)
        field.placeholderString = "Type :fire or :wave"
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.setAccessibilityLabel("Try Colon")
        field.delegate = context.coordinator
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // AppKit callbacks publish state; defer them out of SwiftUI's update pass.
        context.coordinator.scheduleSynchronization()
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.detach()
        field.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let viewModel: BuildInformationViewModel
        weak var field: NSTextField?
        private weak var editor: NSTextView?
        private var synchronizing = false
        private var synchronizationScheduled = false
        private var lastCaretRequest = 0

        init(viewModel: BuildInformationViewModel) { self.viewModel = viewModel }

        deinit { NotificationCenter.default.removeObserver(self) }

        func scheduleSynchronization() {
            guard synchronizationScheduled == false else { return }
            synchronizationScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let field = self.field else { return }
                self.synchronizationScheduled = false
                self.synchronizeModelToField()
                if self.viewModel.testFieldFocusRequested, let window = field.window {
                    window.makeFirstResponder(field)
                }
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field, let editor = field.currentEditor() as? NSTextView else { return }
            NotificationCenter.default.removeObserver(self)
            self.editor = editor
            NotificationCenter.default.addObserver(self, selector: #selector(editorChanged),
                name: NSTextView.didChangeSelectionNotification, object: editor)
            if let clipView = field.enclosingScrollView?.contentView {
                NotificationCenter.default.addObserver(self, selector: #selector(editorChanged),
                    name: NSView.boundsDidChangeNotification, object: clipView)
            }
            if let window = field.window {
                NotificationCenter.default.addObserver(self, selector: #selector(editorChanged),
                    name: NSWindow.didMoveNotification, object: window)
                NotificationCenter.default.addObserver(self, selector: #selector(editorChanged),
                    name: NSWindow.didResizeNotification, object: window)
            }
            viewModel.testFieldFocusChanged(true)
            publishSnapshot(editor)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let editor else { return }
            publishSnapshot(editor)
        }

        func controlTextDidEndEditing(_ notification: Notification) { detach() }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            editor = nil
            viewModel.testFieldFocusChanged(false)
        }

        @objc private func editorChanged(_ notification: Notification) {
            guard let editor else { return }
            publishSnapshot(editor)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            handleCommand(selector, modifiers: NSApp.currentEvent?.modifierFlags ?? [], editor: textView)
        }

        func handleCommand(_ selector: Selector, modifiers: NSEvent.ModifierFlags, editor: NSTextView) -> Bool {
            guard modifiers.intersection([.command, .control, .option, .shift]).isEmpty,
                  editor.hasMarkedText() == false,
                  let key = Self.pickerKey(for: selector)
            else { return false }
            publishSnapshot(editor)
            guard viewModel.handleTestFieldKey(key) else { return false }
            synchronizeModelToField(editor: editor)
            return true
        }

        static func pickerKey(for selector: Selector) -> TestFieldKey? {
            switch NSStringFromSelector(selector) {
            case "insertTab:": .tab
            case "insertNewline:": .enter
            case "moveUp:": .up
            case "moveDown:": .down
            case "cancelOperation:": .escape
            default: nil
            }
        }

        private func publishSnapshot(_ editor: NSTextView) {
            guard synchronizing == false else { return }
            let range = editor.selectedRange()
            var actualRange = NSRange(location: NSNotFound, length: 0)
            let rect = field?.visibleRect.isEmpty == true ? NSRect.zero
                : editor.firstRect(forCharacterRange: range, actualRange: &actualRange)
            viewModel.testFieldEdited(
                text: editor.string,
                selection: editor.hasMarkedText() ? nil : range,
                caretRect: rect
            )
        }

        private func synchronizeModelToField(editor suppliedEditor: NSTextView? = nil) {
            guard synchronizing == false else { return }
            synchronizing = true
            let activeEditor = suppliedEditor ?? editor
            if let activeEditor {
                if activeEditor.string != viewModel.tokenText {
                    // Use the native editor operation so Undo restores the shortcode.
                    activeEditor.insertText(viewModel.tokenText,
                        replacementRange: NSRange(location: 0, length: (activeEditor.string as NSString).length))
                }
                if lastCaretRequest != viewModel.testFieldCaretRequest,
                   let offset = viewModel.testFieldCaretUTF16Offset,
                   offset <= (activeEditor.string as NSString).length {
                    activeEditor.setSelectedRange(NSRange(location: offset, length: 0))
                }
            } else if field?.stringValue != viewModel.tokenText {
                field?.stringValue = viewModel.tokenText
            }
            lastCaretRequest = viewModel.testFieldCaretRequest
            synchronizing = false
        }
    }
}
