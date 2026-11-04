import AppKit
import Carbon.HIToolbox
import ColonEmojiData
import ColonModels
import ColonPickerModels
import ColonSearch
import ColonSettingsCore
import ColonTokenization
import InputMethodKit
import OSLog

private final class DistributedSettingsObserverToken: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(_ token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(token)
    }
}

private struct LoadedInputMethodRuntime: Sendable {
    let store: ColonLocalStore
    let settings: ColonSettingsSnapshot
    let searchEngine: EmojiSearchEngine?
}

private actor InputMethodRuntimeCache {
    static let shared = InputMethodRuntimeCache()

    private struct SearchConfiguration: Equatable {
        let customTags: CustomTagsSnapshot
        let skinTonePreferences: SkinTonePreferencesSnapshot
    }

    private struct CachedSearchEngine {
        let configuration: SearchConfiguration
        let engine: EmojiSearchEngine
    }

    private let emojiDataStore = EmojiDataStore()
    private var cachedSearchEngine: CachedSearchEngine?

    func load() throws -> LoadedInputMethodRuntime {
        let store = try ColonLocalStore.userDefault()
        let settings = try store.currentSnapshot()
        let searchEngine: EmojiSearchEngine?
        if settings.isEnabled && SupportedApplication.allCases.contains(where: {
            settings.enabledApps[$0.rawValue] == true
        }) {
            let customTags = try store.currentCustomTags()
            let skinTonePreferences = try store.currentSkinTonePreferences()
            searchEngine = try makeSearchEngine(
                customTags: customTags,
                skinTonePreferences: skinTonePreferences
            )
        } else {
            searchEngine = nil
        }
        return LoadedInputMethodRuntime(
            store: store,
            settings: settings,
            searchEngine: searchEngine
        )
    }

    func recordSkinTonePreference(
        emojiID: EmojiID,
        selectedVariant: String,
        in store: ColonLocalStore
    ) throws {
        try store.recordSkinTonePreference(
            emojiID: emojiID,
            selectedVariant: selectedVariant,
            commitSucceeded: true
        )
    }

    private func makeSearchEngine(
        customTags: CustomTagsSnapshot,
        skinTonePreferences: SkinTonePreferencesSnapshot
    ) throws -> EmojiSearchEngine {
        let configuration = SearchConfiguration(
            customTags: customTags,
            skinTonePreferences: skinTonePreferences
        )
        if let cachedSearchEngine,
           cachedSearchEngine.configuration == configuration
        {
            return cachedSearchEngine.engine
        }

        let dataset = try emojiDataStore.load().dataset
        let engine = EmojiSearchEngine(
            dataset: dataset,
            customTags: customTags,
            skinTonePreferences: skinTonePreferences
        )
        cachedSearchEngine = CachedSearchEngine(
            configuration: configuration,
            engine: engine
        )
        return engine
    }
}

@objc(ColonInputController)
final class ColonInputController: IMKInputController, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "org.colonproject.inputmethod.Colon",
        category: "lifecycle"
    )

    private let sessionID = AutocompleteSessionID(rawValue: UUID().uuidString)
    private let contextReader = MinimalTextContextReader()
    private let tokenDetector = EmojiTokenDetector()
    private let textCommitter = TextCommitter()
    private let inputClientPolicy = InputClientPolicy()
    private var panelController: CandidatePanelController!
    private var skinTonePanelController: SkinTonePanelController!
    private var passthroughPolicy = InputMethodPassthroughPolicy()
    private var stateMachine: AutocompleteStateMachine
    private var store: ColonLocalStore?
    private var settings = ColonSettingsSnapshot.defaults
    private var searchEngine: EmojiSearchEngine?
    private var runtimeLoadGeneration = 0
    private var runtimeReady = false
    private var latestCaretRect: NSRect?
    private var candidatePanelCallbackToken: String?
    private var skinTonePanelCallbackToken: String?
    private var settingsObserver: DistributedSettingsObserverToken?

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        stateMachine = AutocompleteStateMachine(activeSessionID: sessionID)
        super.init(server: server, delegate: delegate, client: inputClient)
        MainActor.assumeIsolated {
            panelController = CandidatePanelController()
            skinTonePanelController = SkinTonePanelController()
            panelController.onSelection = { [weak self] emojiID, tokenID in
                self?.handleCandidateSelection(emojiID: emojiID, tokenID: tokenID)
            }
            skinTonePanelController.onSelection = { [weak self] selectedIndex, tokenID in
                self?.handleSkinToneSelection(index: selectedIndex, tokenID: tokenID)
            }
            settingsObserver = DistributedSettingsObserverToken(
                DistributedNotificationCenter.default().addObserver(
                    forName: SettingsChangeNotification.name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.settingsDidChange()
                    }
                }
            )
        }
        Self.logger.notice("event=controller_created")
    }

    override func activateServer(_ sender: Any!) {
        MainActor.assumeIsolated {
            passthroughPolicy.activate()
            loadRuntime()
        }
        Self.logger.notice("event=session_activated")
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(
            NSEvent.EventTypeMask.keyDown
                .union([.leftMouseDown, .leftMouseUp])
                .rawValue
        )
    }

    override func deactivateServer(_ sender: Any!) {
        MainActor.assumeIsolated {
            passthroughPolicy.deactivate()
            NSObject.cancelPreviousPerformRequests(
                withTarget: self,
                selector: #selector(refreshAfterHostEdit),
                object: nil
            )
            _ = stateMachine.handle(.sessionChanged(sessionID))
            candidatePanelCallbackToken = nil
            skinTonePanelCallbackToken = nil
            panelController.hide()
            skinTonePanelController.hide()
        }
        Self.logger.notice("event=session_deactivated")
    }

    override func hidePalettes() {
        MainActor.assumeIsolated {
            resetPresentation()
        }
    }

    override func inputControllerWillClose() {
        MainActor.assumeIsolated {
            passthroughPolicy.deactivate()
            resetPresentation()
        }
        Self.logger.notice("event=session_closed")
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else {
            return false
        }
        if event.type == .leftMouseDown {
            MainActor.assumeIsolated {
                if passthroughPolicy.shouldRespondToMouseActivation(
                    isRuntimeReady: runtimeReady
                ) {
                    resetPresentation()
                }
            }
            return false
        }
        if event.type == .leftMouseUp {
            MainActor.assumeIsolated {
                guard passthroughPolicy.shouldRespondToMouseActivation(
                    isRuntimeReady: runtimeReady
                ) else {
                    return
                }
                scheduleRefreshAfterHostEdit()
            }
            return false
        }
        let isKeyDown = event.type == .keyDown
        guard isKeyDown else {
            return false
        }
        let keyCode = event.keyCode
        let characters = event.characters
        let hasSystemShortcutModifier = event.modifierFlags.intersection(
            [.command, .control, .option]
        ).isEmpty == false
        let hasShiftModifier = event.modifierFlags.contains(.shift)
        return MainActor.assumeIsolated {
            guard runtimeReady,
                  passthroughPolicy.shouldScheduleHostRefresh(
                isKeyDown: isKeyDown,
                keyCode: keyCode,
                hasActiveToken: isTrackingTokenState,
                characters: characters,
                hasSystemShortcutModifier: hasSystemShortcutModifier
            ) else {
                return false
            }
            guard validatedClient() != nil else {
                resetPresentation()
                return false
            }
            if handleKeyEvent(
                isKeyDown: isKeyDown,
                keyCode: keyCode,
                characters: characters,
                hasSystemShortcutModifier: hasSystemShortcutModifier,
                hasShiftModifier: hasShiftModifier
            ) {
                return true
            }

            scheduleRefreshAfterHostEdit()
            return passthroughPolicy.shouldConsumeKeyEvent()
        }
    }

    @MainActor
    private func handleKeyEvent(
        isKeyDown: Bool,
        keyCode: UInt16,
        characters: String?,
        hasSystemShortcutModifier: Bool,
        hasShiftModifier: Bool
    ) -> Bool {
        guard isKeyDown else {
            return false
        }

        if characters == ":", hasSystemShortcutModifier == false {
            return handleClosingColon()
        }

        if hasSystemShortcutModifier == false, hasShiftModifier == false,
           [UInt16(36), 48, 53, 76, 125, 126].contains(keyCode), isTrackingTokenState {
            // The host may have applied the last edit before our deferred callback.
            // Read that edit once before handling a picker command, then cancel
            // the redundant callback below. Ordinary typing stays on the cheap path.
            refreshAfterHostEdit()
        }
        guard latestCaretRect != nil,
              passthroughPolicy.shouldHandlePickerKeyEvent(
            isKeyDown: isKeyDown,
            keyCode: keyCode,
            hasSystemShortcutModifier: hasSystemShortcutModifier,
            hasShiftModifier: hasShiftModifier,
            hasPickerState: isCandidateOrToneState
        ) else {
            return false
        }

        let pickerEvent: AutocompleteEvent
        switch keyCode {
        case 125: pickerEvent = .down
        case 126: pickerEvent = .up
        case 36, 76: pickerEvent = .enter
        case 48: pickerEvent = .tab
        case 53: pickerEvent = .escape
        default: return false
        }
        // A pending post-edit callback must not reset tone navigation after Tab.
        NSObject.cancelPreviousPerformRequests(withTarget: self,
            selector: #selector(refreshAfterHostEdit), object: nil)
        let effects = stateMachine.handle(pickerEvent)
        let didCommit = apply(effects: effects)
        if keyCode == 36 || keyCode == 76 { return didCommit }
        return effects.contains { if case .passThrough = $0 { true } else { false } } == false

    }

    @MainActor
    private var isCandidateOrToneState: Bool {
        switch stateMachine.state {
        case .candidates, .skinTones, .correcting:
            true
        default:
            false
        }
    }

    @MainActor
    private var isTrackingTokenState: Bool {
        switch stateMachine.state {
        case .trackingColon, .candidates, .noResultsHidden, .correcting, .skinTones, .dismissed, .committing:
            true
        case .idle:
            false
        }
    }

    @MainActor
    private func handleClosingColon() -> Bool {
        guard latestCaretRect != nil,
              case .candidates(let selection) = stateMachine.state else {
            return false
        }
        return apply(
            effects: stateMachine.handle(
                .textMutation(
                    .closingColon(
                        context: selection.context,
                        candidates: selection.candidates
                    )
                )
            )
        )
    }

    @MainActor
    private func scheduleRefreshAfterHostEdit() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(refreshAfterHostEdit),
            object: nil
        )
        perform(#selector(refreshAfterHostEdit), with: nil, afterDelay: 0)
    }

    @MainActor @objc private func refreshAfterHostEdit() {
        guard runtimeReady,
              passthroughPolicy.state == .active,
              let adapter = validatedClient(),
              let context = contextReader.read(from: adapter)
        else {
            resetPresentation()
            return
        }

        let detection = tokenDetector.detect(in: context.snapshot)
        let mutation: AutocompleteTextMutation
        var shouldUpdateCaretRect = false
        switch detection.state {
        case .colonOnly:
            guard let tokenContext = makeTokenContext(
                detection: detection,
                minimalContext: context,
                query: ""
            ) else {
                resetPresentation()
                return
            }
            mutation = .colonOnly(tokenContext)
            shouldUpdateCaretRect = true
        case .activeQuery, .closingColonIntent:
            guard let query = detection.normalizedQuery,
                  let tokenContext = makeTokenContext(
                    detection: detection,
                    minimalContext: context,
                    query: query
                  )
            else {
                resetPresentation()
                return
            }
            let candidates = searchEngine?.search(
                query: query,
                maximumResultCount: settings.maximumResultCount
            ) ?? []
            mutation = detection.state == .closingColonIntent
                ? .closingColon(context: tokenContext, candidates: candidates)
                : .active(context: tokenContext, candidates: candidates)
            shouldUpdateCaretRect = detection.state == .activeQuery
        case .inactive, .terminatedOrInvalid:
            mutation = .inactive(sessionID: sessionID)
        }
        if shouldUpdateCaretRect {
            latestCaretRect = adapter.caretRect()
        }
        apply(effects: stateMachine.handle(.textMutation(mutation)))
    }

    @MainActor
    private func makeTokenContext(
        detection: EmojiTokenDetection,
        minimalContext: MinimalTextContext,
        query: String
    ) -> AutocompleteTokenContext? {
        guard let localRange = detection.replacementRange,
              minimalContext.hasKnownTokenStart(at: localRange.location),
              let documentRange = minimalContext.documentRange(for: localRange)
        else {
            return nil
        }
        return AutocompleteTokenContext(
            sessionID: sessionID,
            tokenID: "\(sessionID.rawValue):\(documentRange.location)",
            normalizedQuery: query,
            replacementRange: documentRange
        )
    }

    @MainActor
    @discardableResult
    private func apply(effects: [AutocompleteEffect]) -> Bool {
        var didCommit = false
        for effect in effects {
            switch effect {
            case .showCandidates(let selection):
                skinTonePanelCallbackToken = nil
                skinTonePanelController.hide()
                showPanel(selection)
            case .showCorrection(let context, let previousSelection):
                skinTonePanelCallbackToken = nil
                skinTonePanelController.hide()
                showPanel(previousSelection, correctionMessage: context.normalizedQuery.isEmpty
                    ? "Keep typing an emoji name" : "No matches — edit your shortcode")
            case .hidePanel:
                candidatePanelCallbackToken = nil
                skinTonePanelCallbackToken = nil
                panelController.hide()
                skinTonePanelController.hide()
            case .showSkinTones(let selection):
                candidatePanelCallbackToken = nil
                panelController.hide()
                showSkinTonePanel(selection)
            case .commit(let request):
                didCommit = commit(request)
            case .passThrough:
                break
            }
        }
        return didCommit
    }

    @MainActor
    private func showPanel(_ selection: CandidateSelection, correctionMessage: String? = nil) {
        guard let latestCaretRect, let visibleScreenFrame = screenFrameForLatestCaret else {
            candidatePanelCallbackToken = nil
            panelController.hide()
            return
        }
        let appearance: CandidatePanelAppearance = switch settings.appearance {
        case .system: .system
        case .light: .light
        case .dark: .dark
        }
        let callbackToken = "\(selection.context.tokenID):\(UUID().uuidString)"
        candidatePanelCallbackToken = correctionMessage == nil ? callbackToken : nil
        panelController.show(
            selection: selection,
            sessionToken: callbackToken,
            anchorRect: latestCaretRect,
            visibleScreenFrame: visibleScreenFrame,
            visibleRowCount: settings.visibleRowCount,
            size: settings.pickerSize,
            appearance: appearance,
            correctionMessage: correctionMessage
        )
    }

    @MainActor
    private func showSkinTonePanel(_ selection: SkinToneSelection) {
        guard let latestCaretRect, let visibleScreenFrame = screenFrameForLatestCaret else {
            skinTonePanelCallbackToken = nil
            skinTonePanelController.hide()
            return
        }
        let callbackToken = "\(selection.baseSelection.context.tokenID):\(UUID().uuidString)"
        skinTonePanelCallbackToken = callbackToken
        skinTonePanelController.show(
            selection: selection,
            sessionToken: callbackToken,
            anchorRect: latestCaretRect,
            visibleScreenFrame: visibleScreenFrame,
            appearance: panelAppearance
        )
    }

    @MainActor
    private var screenFrameForLatestCaret: NSRect? {
        guard let latestCaretRect else { return nil }
        return NSScreen.screens.first(where: { $0.frame.intersects(latestCaretRect) })?.visibleFrame
    }

    @MainActor
    private var panelAppearance: CandidatePanelAppearance {
        switch settings.appearance {
        case .system: .system
        case .light: .light
        case .dark: .dark
        }
    }

    @MainActor
    private func handleCandidateSelection(emojiID: EmojiID, tokenID: String) {
        guard case .candidates(let selection) = stateMachine.state,
              candidatePanelCallbackToken == tokenID,
              tokenID.hasPrefix("\(selection.context.tokenID):")
        else {
            return
        }
        apply(effects: stateMachine.handle(.mouseSelection(emojiID)))
    }

    @MainActor
    private func handleSkinToneSelection(index: Int, tokenID: String) {
        guard case .skinTones(let selection) = stateMachine.state,
              skinTonePanelCallbackToken == tokenID,
              tokenID.hasPrefix("\(selection.baseSelection.context.tokenID):")
        else {
            return
        }
        apply(effects: stateMachine.handle(.skinToneSelection(index)))
    }

    @MainActor
    private func commit(_ request: CommitRequest) -> Bool {
        defer {
            _ = stateMachine.handle(.commitCompleted)
            candidatePanelCallbackToken = nil
            skinTonePanelCallbackToken = nil
            panelController.hide()
            skinTonePanelController.hide()
        }

        guard latestCaretRect != nil,
              request.context.sessionID == sessionID,
              let adapter = validatedClient()
        else {
            Self.logger.error("event=commit_rejected_context")
            return false
        }

        let outcome = textCommitter.commit(
            TextCommitExpectation(
                normalizedQuery: request.context.normalizedQuery,
                documentRange: request.context.replacementRange,
                replacementText: request.renderedEmoji
            ),
            to: adapter
        )
        guard outcome.didCommit else {
            Self.logger.error("event=commit_rejected_stale_token")
            return false
        }

        if request.trigger == .skinTone {
            persistSkinTonePreference(request)
        }
        Self.logger.notice("event=commit_succeeded trigger=\(request.trigger.rawValue, privacy: .public)")
        return true
    }

    @MainActor
    private func persistSkinTonePreference(_ request: CommitRequest) {
        guard let store else {
            Self.logger.error("event=skin_tone_persistence_failed")
            return
        }
        Task { @MainActor [weak self] in
            do {
                try await InputMethodRuntimeCache.shared.recordSkinTonePreference(
                    emojiID: request.candidate.id,
                    selectedVariant: request.renderedEmoji,
                    in: store
                )
                self?.loadRuntime()
            } catch {
                Self.logger.error("event=skin_tone_persistence_failed")
            }
        }
    }

    @MainActor
    private func validatedClient() -> InputMethodTextClientAdapter? {
        guard runtimeReady,
              let currentClient = client(),
              let adapter = InputMethodTextClientAdapter(client: currentClient)
        else {
            return nil
        }
        let context = InputClientSecurityContext(
            clientBundleIdentifier: adapter.bundleIdentifier,
            frontmostBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            secureEventInputEnabled: IsSecureEventInputEnabled()
        )
        guard inputClientPolicy.decision(context: context, settings: settings) == .allowed else {
            return nil
        }
        return adapter
    }

    @MainActor
    private func settingsDidChange() {
        guard passthroughPolicy.state == .active else {
            return
        }
        loadRuntime()
    }

    @MainActor
    private func resetPresentation() {
        latestCaretRect = nil
        apply(
            effects: stateMachine.handle(
                .textMutation(.inactive(sessionID: sessionID))
            )
        )
    }

    @MainActor
    private func loadRuntime() {
        runtimeLoadGeneration += 1
        let generation = runtimeLoadGeneration
        runtimeReady = false
        resetPresentation()

        Task { @MainActor [weak self] in
            do {
                let runtime = try await InputMethodRuntimeCache.shared.load()
                guard let self,
                      self.runtimeLoadGeneration == generation
                else {
                    return
                }
                self.store = runtime.store
                self.settings = runtime.settings
                self.searchEngine = runtime.searchEngine
                self.runtimeReady = true
                Self.logger.notice("event=runtime_loaded")

                guard self.passthroughPolicy.state == .active else {
                    return
                }
                guard self.validatedClient() != nil else {
                    self.resetPresentation()
                    return
                }
                self.scheduleRefreshAfterHostEdit()
            } catch {
                guard let self,
                      self.runtimeLoadGeneration == generation
                else {
                    return
                }
                self.store = nil
                self.settings = .defaults
                self.settings.isEnabled = false
                self.searchEngine = nil
                self.runtimeReady = false
                self.resetPresentation()
                Self.logger.error("event=runtime_load_failed")
            }
        }
    }

    deinit {
        Self.logger.notice("event=controller_destroyed")
    }
}
