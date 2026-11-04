import AppKit
import ColonModels
import ColonPickerModels
import SwiftUI

private final class NonactivatingSkinTonePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SkinTonePanelController {
    var onSelection: ((Int, String) -> Void)?

    private let panel: NSPanel
    private var sessionGate = CandidatePanelSessionGate()
    private var presentationModel: SkinTonePresentationModel?

    init() {
        panel = NonactivatingSkinTonePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
    }

    func show(
        selection: SkinToneSelection,
        sessionToken: String,
        anchorRect: NSRect,
        visibleScreenFrame: NSRect,
        appearance: CandidatePanelAppearance
    ) {
        sessionGate.begin(token: sessionToken)
        let accessibility = CandidatePanelAccessibility(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        )
        let model = SkinTonePanelViewModel(
            selection: selection,
            appearance: appearance,
            accessibility: accessibility
        )
        if let presentationModel {
            presentationModel.update(model: model, sessionToken: sessionToken)
        } else {
            let presentationModel = SkinTonePresentationModel(model: model, sessionToken: sessionToken)
            let content = SkinTonePanelContentView(presentationModel: presentationModel) { [weak self] index, renderedToken in
                guard let self, self.sessionGate.accepts(token: renderedToken) else {
                    return
                }
                self.onSelection?(index, renderedToken)
            }
            self.presentationModel = presentationModel
            panel.contentViewController = NSHostingController(rootView: content)
        }
        panel.appearance = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        panel.animationBehavior = accessibility.reduceMotion ? .none : .utilityWindow

        let width = min(420, max(56, Double(model.items.count) * 52))
        let frame = CandidatePanelPositioner.frame(
            anchor: PanelRect(
                x: anchorRect.minX,
                y: anchorRect.minY,
                width: anchorRect.width,
                height: anchorRect.height
            ),
            panelSize: PanelSize(width: width, height: 56),
            visibleScreen: PanelRect(
                x: visibleScreenFrame.minX,
                y: visibleScreenFrame.minY,
                width: visibleScreenFrame.width,
                height: visibleScreenFrame.height
            )
        )
        let panelFrame = NSRect(x: frame.minX, y: frame.minY, width: frame.size.width, height: frame.size.height)
        if panel.frame != panelFrame {
            panel.setFrame(panelFrame, display: true)
        }
        if panel.isVisible == false {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        sessionGate.invalidate()
        panel.orderOut(nil)
    }
}

@MainActor
private final class SkinTonePresentationModel: ObservableObject {
    @Published private(set) var model: SkinTonePanelViewModel
    private(set) var sessionToken: String

    init(model: SkinTonePanelViewModel, sessionToken: String) {
        self.model = model
        self.sessionToken = sessionToken
    }

    func update(model: SkinTonePanelViewModel, sessionToken: String) {
        self.sessionToken = sessionToken
        self.model = model
    }
}

private struct SkinTonePanelContentView: View {
    @ObservedObject var presentationModel: SkinTonePresentationModel
    let onSelection: (Int, String) -> Void

    private var model: SkinTonePanelViewModel { presentationModel.model }

    var body: some View {
        let renderedToken = presentationModel.sessionToken
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(model.items) { item in
                    Button {
                        onSelection(item.id, renderedToken)
                    } label: {
                        SkinToneItemView(
                            item: item,
                            increaseContrast: model.accessibility.increaseContrast
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.accessibilityLabel)
                }
            }
        }
        .scrollIndicators(.automatic)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.primary.opacity(model.accessibility.increaseContrast ? 0.8 : 0.18), lineWidth: model.accessibility.increaseContrast ? 2 : 1)
        }
    }
}

private struct SkinToneItemView: View {
    let item: SkinTonePanelItem
    let increaseContrast: Bool

    var body: some View {
        Text(item.emoji)
            .font(.system(size: 28))
            .frame(width: 52, height: 56)
            .background(selectionBackground)
            .contentShape(Rectangle())
    }

    private var selectionBackground: Color {
        guard item.isSelected else {
            return .clear
        }
        return Color.accentColor.opacity(increaseContrast ? 0.36 : 0.22)
    }
}
