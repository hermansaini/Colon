import AppKit
import ColonModels
import ColonPickerModels
import SwiftUI

private final class NonactivatingCandidatePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CandidatePanelController {
    var onSelection: ((EmojiID, String) -> Void)?

    private let panel: NSPanel
    private var sessionGate = CandidatePanelSessionGate()
    private var presentationModel: CandidatePanelPresentationModel?

    init() {
        panel = NonactivatingCandidatePanel(
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
        selection: CandidateSelection,
        sessionToken: String,
        anchorRect: NSRect,
        visibleScreenFrame: NSRect,
        visibleRowCount: Int,
        size: PickerSize,
        appearance: CandidatePanelAppearance,
        correctionMessage: String? = nil
    ) {
        sessionGate.begin(token: sessionToken)
        let accessibility = CandidatePanelAccessibility(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        )
        let model = CandidatePanelViewModel(
            selection: selection,
            visibleRowCount: visibleRowCount,
            size: size,
            appearance: appearance,
            accessibility: accessibility,
            correctionMessage: correctionMessage
        )
        if let presentationModel {
            presentationModel.update(model: model, sessionToken: sessionToken)
        } else {
            let presentationModel = CandidatePanelPresentationModel(model: model, sessionToken: sessionToken)
            let content = CandidatePanelContentView(
                presentationModel: presentationModel
            ) { [weak self] emojiID, renderedToken in
                guard let self,
                      self.sessionGate.accepts(token: renderedToken)
                else {
                    return
                }
                self.onSelection?(emojiID, renderedToken)
            }
            self.presentationModel = presentationModel
            panel.contentViewController = NSHostingController(rootView: content)
        }
        panel.appearance = nsAppearance(for: appearance)
        panel.animationBehavior = accessibility.reduceMotion ? .none : .utilityWindow

        let frame = CandidatePanelPositioner.frame(
            anchor: PanelRect(
                x: anchorRect.minX,
                y: anchorRect.minY,
                width: anchorRect.width,
                height: anchorRect.height
            ),
            panelSize: PanelSize(width: model.metrics.width, height: model.contentHeight),
            visibleScreen: PanelRect(
                x: visibleScreenFrame.minX,
                y: visibleScreenFrame.minY,
                width: visibleScreenFrame.width,
                height: visibleScreenFrame.height
            )
        )
        let panelFrame = NSRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.size.width,
            height: frame.size.height
        )
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

    private func nsAppearance(for appearance: CandidatePanelAppearance) -> NSAppearance? {
        switch appearance {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
private final class CandidatePanelPresentationModel: ObservableObject {
    @Published private(set) var state: CandidatePanelPresentationState
    private(set) var sessionToken: String

    init(model: CandidatePanelViewModel, sessionToken: String) {
        self.sessionToken = sessionToken
        state = CandidatePanelPresentationState(model: model)
    }

    func update(model: CandidatePanelViewModel, sessionToken: String) {
        self.sessionToken = sessionToken
        state.update(model: model)
    }
}

private struct CandidatePanelContentView: View {
    @ObservedObject var presentationModel: CandidatePanelPresentationModel
    let onSelection: (EmojiID, String) -> Void

    private var model: CandidatePanelViewModel {
        presentationModel.state.model
    }

    var body: some View {
        let renderedToken = presentationModel.sessionToken
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(model.rows) { row in
                            Button {
                                onSelection(row.id, renderedToken)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(row.emoji)
                                        .font(.system(size: max(20, model.metrics.rowHeight * 0.48)))
                                        .frame(width: model.metrics.rowHeight * 0.72)

                                    Text(":\(row.canonicalAlias):")
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 4)
                                }
                                .padding(.horizontal, model.metrics.horizontalPadding)
                                .frame(height: model.metrics.rowHeight)
                                .contentShape(Rectangle())
                                .background(
                                    row.isSelected
                                        ? Color.accentColor.opacity(model.accessibility.increaseContrast ? 0.32 : 0.2)
                                        : Color.clear
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(model.correctionMessage != nil)
                            .opacity(model.correctionMessage == nil ? 1 : 0.45)
                            .id(row.id)
                            .accessibilityLabel(
                                row.matchingHint.map {
                                    "\(row.canonicalName), matched \($0)"
                                } ?? row.canonicalName
                            )
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .onAppear {
                    scrollSelection(
                        target: presentationModel.state.scrollTarget,
                        proxy: proxy
                    )
                }
                .onChange(of: presentationModel.state.scrollTarget) { _, target in
                    scrollSelection(target: target, proxy: proxy)
                }
            }
            if let message = model.correctionMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, model.metrics.horizontalPadding)
                    .frame(height: 28)
            }
        }
        .frame(width: model.metrics.width, height: model.contentHeight)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.primary.opacity(model.accessibility.increaseContrast ? 0.8 : 0.18), lineWidth: model.accessibility.increaseContrast ? 2 : 1)
        }
    }

    private func scrollSelection(
        target: CandidatePanelScrollTarget,
        proxy: ScrollViewProxy
    ) {
        guard let selectedRowID = target.rowID else {
            return
        }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            proxy.scrollTo(selectedRowID)
        }
    }
}
