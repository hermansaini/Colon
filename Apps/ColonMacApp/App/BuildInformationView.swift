import AppKit
import ColonEmojiData
import ColonModels
import ColonPickerModels
import ColonSearch
import ColonSettingsCore
import ColonTokenization
import ServiceManagement
import SwiftUI

private final class DistributedObserverToken: @unchecked Sendable {
    let value: NSObjectProtocol

    init(_ value: NSObjectProtocol) {
        self.value = value
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(value)
    }
}

private struct SilentSettingsChangePoster: SettingsChangePosting {
    func postSettingsChanged() {}
}

private final class ApplicationObserverToken: @unchecked Sendable {
    private let value: NSObjectProtocol

    init(_ value: NSObjectProtocol) {
        self.value = value
    }

    deinit {
        NotificationCenter.default.removeObserver(value)
    }
}

struct TokenVisualizationSegments {
    let prefix: String
    let token: String
    let suffix: String
}

struct EmojiBrowserRow: Identifiable, Sendable {
    let id: EmojiID
    let emoji: String
    let canonicalName: String
    let canonicalAlias: String
    let searchableName: String
}

enum TestFieldKey {
    case up
    case down
    case enter
    case tab
    case escape
}

private struct EmojiBrowserLoadResult: Sendable {
    let dataset: EmojiDataset
    let rows: [EmojiBrowserRow]
    let summary: String
}

private struct PersistedCompanionState: Sendable {
    let settings: ColonSettingsSnapshot
    let customTags: CustomTagsSnapshot
    let skinTonePreferences: SkinTonePreferencesSnapshot
}

private struct CustomTagSearchState: Sendable {
    let customTags: CustomTagsSnapshot
    let skinTonePreferences: SkinTonePreferencesSnapshot
}

private struct InitialPersistedState: Sendable {
    let state: PersistedCompanionState
    let recoveredDamagedFile: Bool
}

@MainActor
final class BuildInformationViewModel: ObservableObject {
    @Published private(set) var isEnabled = true
    @Published private(set) var statusMessage: String?
    @Published var tokenText = "hello :fist" {
        didSet {
            if updatingTestFieldSnapshot == false {
                testFieldSelectionText = nil
                updateAutocomplete()
            }
        }
    }
    @Published private(set) var testFieldCaretRequest = 0
    @Published private(set) var testFieldCaretUTF16Offset: Int?
    @Published private(set) var datasetSummary = "Emoji data unavailable"
    @Published private(set) var interactionStatus = "Idle"
    @Published private(set) var launchAtLoginPreferred = true
    @Published private(set) var menuBarVisible = true
    @Published private(set) var appearancePreference = AppearancePreference.system
    @Published private(set) var pickerSizePreference = PickerSize.standard
    @Published private(set) var visibleRows = 6
    @Published private(set) var maximumResults = 50
    @Published private(set) var enabledApps = ColonSettingsSnapshot.defaults.enabledApps
    @Published private(set) var inputMethodStatus = "Checking input method…"
    @Published private(set) var inputMethodStage = InputMethodOnboardingStage.notInstalled
    @Published private(set) var inputMethodInstallationLocation = InputMethodInstallationLocation.notInstalled
    @Published private(set) var inputMethodRequiresLogout = false
    @Published private(set) var launchAtLoginStatus = "Not registered"
    @Published var selectedSettingsSection = CompanionSettingsTab.general
    @Published private(set) var testFieldFocusRequested = false
    @Published var emojiBrowserQuery = ""
    @Published var selectedEmojiID: EmojiID?
    @Published var customTagInput = ""
    @Published private(set) var emojiBrowserRows: [EmojiBrowserRow] = []

    private let store: ColonLocalStore?
    private let panelController = CandidatePanelController()
    private let skinTonePanelController = SkinTonePanelController()
    private var candidateCallbackToken: String?
    private var toneCallbackToken: String?
    private let inputMethodInstallationController = InputMethodInstallationController()
    private let diagnosticEvents = DiagnosticEventBuffer()
    private let presentsNativePanels: Bool
    private var searchEngine: EmojiSearchEngine?
    private var emojiDataset: EmojiDataset?
    private var customTagsSnapshot = CustomTagsSnapshot.defaults
    private var skinTonePreferencesSnapshot = SkinTonePreferencesSnapshot.defaults
    private var maximumResultCount = 50
    private var visibleRowCount = 6
    private var pickerSize = PickerSize.standard
    private var panelAppearance = CandidatePanelAppearance.system
    private var stateMachine = AutocompleteStateMachine(
        activeSessionID: AutocompleteSessionID(rawValue: "companion")
    )
    private var settingsObserver: DistributedObserverToken?
    private var applicationObservers: [ApplicationObserverToken] = []
    private var applicationIsActive = true
    private var testFieldIsFocused = false
    private var testFieldHasSelectedText = false
    private var testFieldSelectionText: String?
    private var updatingTestFieldSnapshot = false
    private var testFieldCaretRect: NSRect?
    private var searchIndexPending = false
    private var customTagMutationInFlight = false
    private var persistedReloadPending = false
    private var tonePreferenceWriteInFlight = false
    private var searchEngineBuildInFlight = false
    private let usesSystemServices: Bool
    private var settingsWriteTask: Task<Void, Never>?
    private var tonePreferenceWriteTask: Task<Void, Never>?
    private var customTagMutationTask: Task<Void, Never>?
    private var persistedReloadTask: Task<Void, Never>?
    private var searchEngineBuildTask: Task<Void, Never>?
    private var initialLoadTask: Task<Void, Never>?
    private var currentSettingsSnapshot = ColonSettingsSnapshot.defaults
    private var tonePreferenceWriteGeneration = 0
    private var customTagMutationGeneration = 0
    private var persistedReloadGeneration = 0
    private var persistedReloadRequestGeneration = 0
    private var searchEngineBuildGeneration = 0

    private var searchIndexUnavailable: Bool {
        searchEngine == nil
            || searchIndexPending
            || customTagMutationInFlight
            || persistedReloadPending
            || tonePreferenceWriteInFlight
            || searchEngineBuildInFlight
    }

    init(
        storagePaths: ColonStoragePaths? = nil,
        startsSystemServices: Bool = true,
        presentsNativePanels: Bool? = nil
    ) {
        usesSystemServices = startsSystemServices
        self.presentsNativePanels = presentsNativePanels ?? startsSystemServices
        do {
            let paths = try storagePaths ?? ColonStoragePaths.userApplicationSupport()
            let poster: any SettingsChangePosting = startsSystemServices
                ? DistributedSettingsChangePoster()
                : SilentSettingsChangePoster()
            let store = try ColonLocalStore(paths: paths, changePoster: poster)
            self.store = store
        } catch {
            self.store = nil
            statusMessage = "Settings are temporarily unavailable."
        }

        panelController.onSelection = { [weak self] emojiID, sessionToken in
            guard let self,
                  case .candidates = self.stateMachine.state,
                  self.candidateCallbackToken == sessionToken
            else {
                return
            }
            self.send(.mouseSelection(emojiID))
        }
        skinTonePanelController.onSelection = { [weak self] index, sessionToken in
            guard let self,
                  case .skinTones = self.stateMachine.state,
                  self.toneCallbackToken == sessionToken
            else {
                return
            }
            self.send(.skinToneSelection(index))
        }
        if startsSystemServices {
            settingsObserver = DistributedObserverToken(
                DistributedNotificationCenter.default().addObserver(
                    forName: SettingsChangeNotification.name,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard notification.userInfo?[SettingsChangeNotification.originKey] as? String
                            != SettingsChangeNotification.processOrigin
                    else {
                        return
                    }
                    Task { @MainActor in
                        self?.reloadPersistedState()
                    }
                }
            )
            applicationObservers.append(ApplicationObserverToken(
                NotificationCenter.default.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.applicationIsActive = false
                        self?.updateAutocomplete()
                    }
                }
            ))
            applicationObservers.append(ApplicationObserverToken(NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.applicationDidBecomeActive()
                }
            }))
        }

        let store = self.store
        let initialSettingsGeneration = settingsWriteGeneration
        let initialToneGeneration = tonePreferenceWriteGeneration
        let initialTagGeneration = customTagMutationGeneration
        let initialReloadRequestGeneration = persistedReloadRequestGeneration
        let persistedLoadTask = Task.detached(priority: .utility) { () -> InitialPersistedState? in
            guard let store else {
                return nil
            }
            do {
                let state = PersistedCompanionState(
                    settings: try store.currentSnapshot(),
                    customTags: try store.currentCustomTags(),
                    skinTonePreferences: try store.currentSkinTonePreferences()
                )
                return InitialPersistedState(
                    state: state,
                    recoveredDamagedFile: store.storageRecoveryNotices().isEmpty == false
                )
            } catch {
                return nil
            }
        }
        let emojiLoadTask = Task.detached(priority: .userInitiated) { () throws -> EmojiBrowserLoadResult in
                let snapshot = try EmojiDataStore().load()
                let metadata = snapshot.dataset.metadata
                let milliseconds = Double(snapshot.metrics.durationNanoseconds) / 1_000_000
                let summary = String(
                    format: "Unicode Emoji %@ • CLDR %@ • %d entries • %.1f ms load",
                    metadata.unicodeEmojiVersion,
                    metadata.cldrVersion,
                    snapshot.dataset.entries.count,
                    milliseconds
                )
                let rows = snapshot.dataset.entries.map {
                    EmojiBrowserRow(
                        id: $0.id,
                        emoji: $0.emoji,
                        canonicalName: $0.canonicalName,
                        canonicalAlias: $0.canonicalAlias,
                        searchableName: $0.canonicalName.lowercased()
                    )
                }
                return EmojiBrowserLoadResult(
                    dataset: snapshot.dataset,
                    rows: rows,
                    summary: summary
                )
        }
        initialLoadTask = Task { [weak self] in
            let persistedState = await persistedLoadTask.value
            if let self {
                if let persistedState {
                    self.applyInitialPersistedState(
                        persistedState,
                        appliesSettings: self.settingsWriteGeneration == initialSettingsGeneration
                            && self.persistedReloadRequestGeneration == initialReloadRequestGeneration,
                        appliesCustomTags: self.customTagMutationGeneration == initialTagGeneration
                            && self.persistedReloadRequestGeneration == initialReloadRequestGeneration,
                        appliesSkinTonePreferences: self.tonePreferenceWriteGeneration == initialToneGeneration
                            && self.persistedReloadRequestGeneration == initialReloadRequestGeneration
                    )
                } else if self.statusMessage == nil {
                    self.statusMessage = "Settings are temporarily unavailable."
                }
            }
            do {
                let result = try await emojiLoadTask.value
                self?.applyEmojiBrowserLoad(result)
            } catch {
                if self?.statusMessage == nil {
                    self?.statusMessage = "Emoji data could not be loaded."
                }
            }
        }

        if startsSystemServices {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.refreshInputMethodReadiness()
                self?.refreshLaunchAtLoginStatus()
            }
        }
    }

    func waitForInitialLoad() async {
        await initialLoadTask?.value
        while true {
            let generation = searchEngineBuildGeneration
            await searchEngineBuildTask?.value
            guard generation != searchEngineBuildGeneration else {
                return
            }
        }
    }

    func waitForPendingSettingsWrites() async {
        while true {
            let settingsGeneration = settingsWriteGeneration
            let toneGeneration = tonePreferenceWriteGeneration
            let tagGeneration = customTagMutationGeneration
            let reloadGeneration = persistedReloadGeneration
            let indexGeneration = searchEngineBuildGeneration
            await settingsWriteTask?.value
            await tonePreferenceWriteTask?.value
            await customTagMutationTask?.value
            await persistedReloadTask?.value
            await searchEngineBuildTask?.value
            guard settingsGeneration != settingsWriteGeneration
                    || toneGeneration != tonePreferenceWriteGeneration
                    || tagGeneration != customTagMutationGeneration
                    || reloadGeneration != persistedReloadGeneration
                    || indexGeneration != searchEngineBuildGeneration
            else {
                return
            }
        }
    }

    func requestTestFieldFocus() {
        selectedSettingsSection = .general
        testFieldFocusRequested = true
    }

    func clearTestFieldFocusRequest() {
        testFieldFocusRequested = false
    }

    func testFieldFocusChanged(_ isFocused: Bool) {
        testFieldIsFocused = isFocused
        if isFocused == false { testFieldCaretRect = nil }
        if isFocused {
            applicationIsActive = true
            clearTestFieldFocusRequest()
        }
        updateAutocomplete()
    }

    /// Consume one coherent native-editor snapshot instead of transient SwiftUI
    /// text/selection updates that momentarily hide the picker on every edit.
    func testFieldEdited(text: String, selection: NSRange?, caretRect: NSRect) {
        updatingTestFieldSnapshot = true
        if tokenText != text { tokenText = text }
        updatingTestFieldSnapshot = false
        testFieldCaretRect = caretRect
        let count = (text as NSString).length
        guard let selection, selection.location != NSNotFound,
              selection.location >= 0, selection.location <= count,
              selection.length >= 0, selection.length <= count - selection.location
        else {
            testFieldHasSelectedText = true
            testFieldCaretUTF16Offset = nil
            testFieldSelectionText = nil
            updateAutocomplete()
            return
        }
        testFieldHasSelectedText = selection.length > 0
        testFieldCaretUTF16Offset = selection.length == 0 ? selection.location : nil
        testFieldSelectionText = text
        updateAutocomplete()
    }

    func testFieldSelectionChanged(_ selection: TextSelection?) {
        guard let selection else {
            testFieldCaretUTF16Offset = nil
            testFieldHasSelectedText = false
            testFieldSelectionText = nil
            updateAutocomplete()
            return
        }
        switch selection.indices {
        case .selection(let range):
            let utf16 = tokenText.utf16
            guard let lowerBound = range.lowerBound.samePosition(in: utf16),
                  let upperBound = range.upperBound.samePosition(in: utf16),
                  lowerBound >= utf16.startIndex,
                  lowerBound <= utf16.endIndex,
                  upperBound >= lowerBound,
                  upperBound <= utf16.endIndex
            else {
                testFieldHasSelectedText = true
                testFieldCaretUTF16Offset = nil
                testFieldSelectionText = nil
                updateAutocomplete()
                return
            }
            let location = utf16.distance(from: utf16.startIndex, to: lowerBound)
            let length = utf16.distance(from: lowerBound, to: upperBound)
            guard length >= 0 else {
                testFieldHasSelectedText = true
                testFieldCaretUTF16Offset = nil
                testFieldSelectionText = nil
                updateAutocomplete()
                return
            }
            testFieldHasSelectedText = length > 0
            testFieldCaretUTF16Offset = length == 0 ? location : nil
        case .multiSelection:
            testFieldHasSelectedText = true
            testFieldCaretUTF16Offset = nil
        @unknown default:
            testFieldHasSelectedText = true
            testFieldCaretUTF16Offset = nil
        }
        testFieldSelectionText = tokenText
        updateAutocomplete()
    }

    func applicationDidBecomeActive() {
        applicationIsActive = true
        updateAutocomplete()
    }

    func handleTestFieldKey(_ key: TestFieldKey) -> Bool {
        guard testFieldIsFocused,
              applicationIsActive,
              isEnabled,
              presentsNativePanels == false || testFieldPanelAnchor != nil,
              searchIndexUnavailable == false,
              testFieldSelectionText == tokenText
        else {
            return false
        }
        let event: AutocompleteEvent = switch key {
        case .up: .up
        case .down: .down
        case .enter: .enter
        case .tab: .tab
        case .escape: .escape
        }
        let effects = stateMachine.handle(event)
        let passedThrough = effects.contains {
            if case .passThrough = $0 { true } else { false }
        }
        projectState(effects: effects)
        return passedThrough == false
    }

    func installInputMethod() {
        guard usesSystemServices else {
            statusMessage = "Input-method installation is unavailable in this test session."
            return
        }
        do {
            try inputMethodInstallationController.install()
            statusMessage = nil
        } catch InputMethodInstallationControllerError.systemManagedInstall {
            statusMessage = "Colon is installed system-wide. Ask your administrator to update or remove it."
        } catch InputMethodInstallationControllerError.multipleCopies {
            statusMessage = "Multiple Colon input-method copies were found. Remove the duplicate through its administrator."
        } catch {
            diagnosticEvents.append(
                DiagnosticEvent(
                    timestamp: Date(),
                    subsystem: .installer,
                    code: .installCopyFailed,
                    metadata: DiagnosticMetadata(errorDomain: .installer)
                )
            )
            statusMessage = "The embedded input method could not be verified or installed."
        }
        refreshInputMethodReadiness()
    }

    func enableAndSelectInputMethod() {
        guard usesSystemServices else {
            statusMessage = "Input-method selection is unavailable in this test session."
            return
        }
        do {
            try inputMethodInstallationController.enableAndSelect()
            statusMessage = nil
        } catch InputMethodInstallationControllerError.multipleCopies {
            statusMessage = "Multiple Colon input-method copies were found. Remove the duplicate through its administrator."
        } catch {
            statusMessage = "Enable Colon in System Settings → Keyboard → Text Input."
        }
        refreshInputMethodReadiness()
    }

    func uninstallInputMethod() {
        guard usesSystemServices else {
            statusMessage = "Input-method removal is unavailable in this test session."
            return
        }
        do {
            try inputMethodInstallationController.uninstall()
            statusMessage = nil
        } catch InputMethodInstallationControllerError.systemManagedInstall {
            statusMessage = "Colon is installed system-wide. Ask your administrator to remove it."
        } catch InputMethodInstallationControllerError.multipleCopies {
            statusMessage = "Multiple Colon input-method copies were found. Remove the duplicate through its administrator."
        } catch InputMethodInstallationControllerError.noEnabledFallbackInputSource {
            statusMessage = "Select another keyboard input source before uninstalling Colon."
        } catch InputMethodInstallationControllerError.fallbackSelectionFailed {
            statusMessage = "Colon could not switch to another keyboard input source, so it was not uninstalled."
        } catch {
            statusMessage = "The installed input method could not be verified or removed."
        }
        refreshInputMethodReadiness()
    }

    func refreshInputMethodReadiness() {
        guard usesSystemServices else {
            inputMethodStatus = "System checks are disabled in this test session."
            return
        }
        let snapshot = inputMethodInstallationController.readiness()
        let state = InputMethodOnboardingState(snapshot: snapshot)
        inputMethodStage = state.stage
        inputMethodInstallationLocation = snapshot.installationLocation
        inputMethodRequiresLogout = state.requiresLogoutOrLogin
        inputMethodStatus = switch snapshot.installationLocation {
        case .systemLibrary:
            "Installed system-wide; updates are administrator-managed"
        case .managedElsewhere:
            "Installed in a managed location"
        case .multipleCopies:
            "Multiple input-method copies detected"
        case .notInstalled, .userLibrary:
            switch state.stage {
            case .notInstalled: "Not installed"
            case .installedAwaitingDiscovery: "Installed; macOS has not discovered it"
            case .discoveredDisabled: "Discovered; enable it in Text Input settings"
            case .enabledNotSelected: "Enabled; select Colon from the input menu"
            case .ready: "Installed, enabled, and selected"
            }
        }
    }

    func refreshLaunchAtLoginStatus() {
        guard usesSystemServices else {
            launchAtLoginStatus = "System checks are disabled in this test session."
            return
        }
        launchAtLoginStatus = switch SMAppService.mainApp.status {
        case .enabled: "Enabled"
        case .notRegistered: "Not registered"
        case .requiresApproval: "Requires approval in System Settings"
        case .notFound: "App must be moved to Applications"
        @unknown default: "Unknown"
        }
    }

    func exportDiagnostics() {
        do {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Local"
            let readiness = usesSystemServices
                ? inputMethodInstallationController.readiness()
                : InputMethodReadinessSnapshot(
                    isInstalled: false,
                    isDiscovered: false,
                    isEnabled: false,
                    isSelected: false
                )
            let report = ColonDiagnosticReport(
                generatedAt: Date(),
                appVersion: "\(version) (\(build))",
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                inputMethodReadiness: readiness,
                events: diagnosticEvents.snapshot()
            )
            let paths = try store?.paths ?? ColonStoragePaths.userApplicationSupport()
            let destination = paths.diagnosticsDirectoryURL.appending(
                path: "colon-diagnostics-\(Int(Date().timeIntervalSince1970)).json"
            )
            try DiagnosticReportEncoder().encode(report).write(to: destination, options: .atomic)
            if usesSystemServices {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
            statusMessage = nil
        } catch {
            statusMessage = "Diagnostics could not be exported."
        }
    }

    func setEnabled(_ enabled: Bool) {
        persistSettings { $0.isEnabled = enabled }
    }

    func setLaunchAtLoginPreferred(_ enabled: Bool) {
        do {
            if usesSystemServices {
                if enabled, SMAppService.mainApp.status == .notRegistered {
                    try SMAppService.mainApp.register()
                } else if enabled == false, SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
            }
            persistSettings { $0.launchAtLoginPreferred = enabled }
            refreshLaunchAtLoginStatus()
        } catch {
            statusMessage = "Launch at login could not be changed. Check Login Items in System Settings."
            refreshLaunchAtLoginStatus()
        }
    }

    func setMenuBarVisible(_ visible: Bool) {
        // MenuBarExtra writes its current visibility back during scene updates.
        // Republishing an unchanged value starts another scene update indefinitely.
        guard visible != menuBarVisible else { return }
        persistSettings { $0.menuBarVisible = visible }
    }

    func setAppearance(_ appearance: AppearancePreference) {
        persistSettings { $0.appearance = appearance }
    }

    func setPickerSize(_ size: PickerSize) {
        persistSettings { $0.pickerSize = size }
    }

    func setVisibleRows(_ count: Int) {
        persistSettings { snapshot in
            snapshot.visibleRowCount = count
            snapshot.maximumResultCount = max(count, snapshot.maximumResultCount)
        }
    }

    func setMaximumResults(_ count: Int) {
        persistSettings { snapshot in
            snapshot.maximumResultCount = max(snapshot.visibleRowCount, count)
        }
    }

    func setApplication(_ application: SupportedApplication, enabled: Bool) {
        persistSettings { snapshot in
            snapshot.enabledApps[application.rawValue] = enabled
        }
    }

    var visibleEmojiBrowserRows: [EmojiBrowserRow] {
        let query = emojiBrowserQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rows = query.isEmpty
            ? emojiBrowserRows
            : emojiBrowserRows.filter {
                $0.canonicalAlias.contains(query) || $0.searchableName.contains(query)
            }
        return Array(rows.prefix(100))
    }

    var selectedEmoji: EmojiBrowserRow? {
        guard let selectedEmojiID else {
            return nil
        }
        return emojiBrowserRows.first { $0.id == selectedEmojiID }
    }

    var selectedEmojiTags: [CustomTagRecord] {
        guard let selectedEmojiID else {
            return []
        }
        return customTagsSnapshot.records
            .filter { $0.emojiID == selectedEmojiID }
            .sorted { $0.normalizedTag < $1.normalizedTag }
    }

    func addCustomTag() {
        guard store != nil, let selectedEmojiID else {
            statusMessage = "Select an emoji before adding a tag."
            return
        }
        let tag = customTagInput
        enqueueCustomTagMutation(clearInputIfMatches: tag) { store in
            _ = try store.addCustomTag(emojiID: selectedEmojiID, tag: tag)
        }
    }

    func removeCustomTag(id: UUID) {
        guard store != nil else {
            statusMessage = "Settings are temporarily unavailable."
            return
        }
        enqueueCustomTagMutation(failureMessage: "The custom tag could not be removed.") { store in
            try store.removeCustomTag(id: id)
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch appearancePreference {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var tokenDetection: EmojiTokenDetection {
        guard testFieldHasSelectedText == false else {
            return .inactive
        }
        let text = tokenText as NSString
        let caretOffset = testFieldCaretUTF16Offset ?? text.length
        guard testFieldSelectionText == tokenText,
              caretOffset >= 0,
              caretOffset <= text.length
        else {
            return .inactive
        }
        return EmojiTokenDetector().detect(
            in: TextContextSnapshot(textBeforeCaret: text.substring(to: caretOffset))
        )
    }

    var tokenVisualization: TokenVisualizationSegments {
        let detection = tokenDetection
        guard detection.state == .colonOnly
                || detection.state == .activeQuery
                || detection.state == .closingColonIntent,
              let range = detection.replacementRange
        else {
            return TokenVisualizationSegments(prefix: tokenText, token: "", suffix: "")
        }

        let text = tokenText as NSString
        guard range.location >= 0, NSMaxRange(range) <= text.length else {
            return TokenVisualizationSegments(prefix: tokenText, token: "", suffix: "")
        }

        return TokenVisualizationSegments(
            prefix: text.substring(to: range.location),
            token: text.substring(with: range),
            suffix: text.substring(from: NSMaxRange(range))
        )
    }

    var tokenStatus: String {
        let detection = tokenDetection
        let rangeDescription = detection.replacementRange.map {
            "UTF-16 range {\($0.location), \($0.length)}"
        } ?? "no range"
        let queryDescription = detection.normalizedQuery.map {
            "query \($0.isEmpty ? "(empty)" : $0)"
        } ?? "no query"
        return "\(detection.state.displayName) • \(rangeDescription) • \(queryDescription)"
    }

    func send(_ event: AutocompleteEvent) {
        guard testFieldIsFocused,
              applicationIsActive,
              isEnabled,
              presentsNativePanels == false || testFieldPanelAnchor != nil,
              searchIndexUnavailable == false,
              testFieldSelectionText == tokenText
        else {
            return
        }
        let effects = stateMachine.handle(event)
        projectState(effects: effects)
    }

    func hidePanel() {
        candidateCallbackToken = nil
        toneCallbackToken = nil
        panelController.hide()
        skinTonePanelController.hide()
    }

    private func updateAutocomplete() {
        guard isEnabled, testFieldIsFocused, applicationIsActive else {
            let sessionID = AutocompleteSessionID(rawValue: "companion")
            let effects = stateMachine.handle(.textMutation(.inactive(sessionID: sessionID)))
            projectState(effects: effects)
            return
        }
        guard searchIndexUnavailable == false else {
            hidePanel()
            interactionStatus = searchEngine == nil ? "Loading emoji search" : "Updating emoji search"
            return
        }
        guard testFieldSelectionText == tokenText else {
            hidePanel()
            interactionStatus = "Waiting for the test-field caret"
            return
        }
        guard presentsNativePanels == false || testFieldPanelAnchor != nil else {
            hidePanel()
            interactionStatus = "Caret position unavailable"
            return
        }

        let detection = tokenDetection
        let sessionID = AutocompleteSessionID(rawValue: "companion")
        let mutation: AutocompleteTextMutation

        switch detection.state {
        case .colonOnly:
            mutation = .colonOnly(tokenContext(detection: detection, query: ""))
        case .activeQuery, .closingColonIntent:
            guard let query = detection.normalizedQuery else {
                mutation = .inactive(sessionID: sessionID)
                break
            }
            let candidates = searchEngine?.search(
                query: query,
                maximumResultCount: maximumResultCount
            ) ?? []
            let context = tokenContext(detection: detection, query: query)
            mutation = detection.state == .closingColonIntent
                ? .closingColon(context: context, candidates: candidates)
                : .active(context: context, candidates: candidates)
        case .inactive, .terminatedOrInvalid:
            mutation = .inactive(sessionID: sessionID)
        }

        let effects = stateMachine.handle(.textMutation(mutation))
        projectState(effects: effects)
    }

    private func tokenContext(
        detection: EmojiTokenDetection,
        query: String
    ) -> AutocompleteTokenContext {
        let location = detection.replacementRange?.location ?? 0
        return AutocompleteTokenContext(
            sessionID: AutocompleteSessionID(rawValue: "companion"),
            tokenID: "token-at-\(location)",
            normalizedQuery: query,
            replacementRange: detection.replacementRange ?? NSRange(location: 0, length: 0)
        )
    }

    private func projectState(effects: [AutocompleteEffect]) {
        switch stateMachine.state {
        case .candidates(let selection):
            skinTonePanelController.hide()
            showPanel(selection)
            interactionStatus = "Candidates • selected \(selection.selectedIndex + 1) of \(selection.candidates.count)"
        case .correcting(let context, let previousSelection):
            skinTonePanelController.hide()
            showPanel(previousSelection, correctionMessage: correctionMessage(for: context))
            interactionStatus = "Correcting shortcode"
        case .trackingColon:
            panelController.hide()
            skinTonePanelController.hide()
            interactionStatus = "Tracking opening colon"
        case .noResultsHidden:
            panelController.hide()
            skinTonePanelController.hide()
            interactionStatus = "No results • panel hidden"
        case .dismissed:
            panelController.hide()
            skinTonePanelController.hide()
            interactionStatus = "Dismissed until token boundary"
        case .committing(let request):
            panelController.hide()
            skinTonePanelController.hide()
            if replaceTestFieldToken(with: request) {
                persistSuccessfulToneCommit(request)
                interactionStatus = "Inserted \(request.renderedEmoji) via \(request.trigger.rawValue)"
                if request.trigger == .skinTone {
                    updateAutocomplete()
                }
            }
        case .skinTones(let selection):
            panelController.hide()
            showSkinTonePanel(selection)
            interactionStatus = "Skin tones • selected \(selection.selectedVariant)"
        case .idle:
            panelController.hide()
            skinTonePanelController.hide()
            interactionStatus = effects.contains(.passThrough(.space))
                ? "Idle • space passed through"
                : "Idle"
        }
    }

    private func refreshPanel() {
        guard isEnabled, testFieldIsFocused, applicationIsActive,
              searchIndexUnavailable == false else {
            hidePanel()
            return
        }
        switch stateMachine.state {
        case .candidates(let selection): showPanel(selection)
        case .skinTones(let selection): showSkinTonePanel(selection)
        case .correcting(let context, let selection):
            showPanel(selection, correctionMessage: correctionMessage(for: context))
        default: hidePanel()
        }
    }

    private func correctionMessage(for context: AutocompleteTokenContext) -> String {
        context.normalizedQuery.isEmpty ? "Keep typing an emoji name" : "No matches — edit your shortcode"
    }

    private var testFieldPanelAnchor: (rect: NSRect, screen: NSRect)? {
        guard let rect = testFieldCaretRect,
              let anchor = CaretAnchorResolver.validated(
                PanelRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height),
                screens: NSScreen.screens.map {
                    PanelRect(x: $0.frame.minX, y: $0.frame.minY, width: $0.frame.width, height: $0.frame.height)
                }
              ) else { return nil }
        let normalized = NSRect(x: anchor.minX, y: anchor.minY, width: anchor.size.width, height: anchor.size.height)
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(normalized) }) else { return nil }
        return (normalized, screen.visibleFrame)
    }

    private func showPanel(_ selection: CandidateSelection, correctionMessage: String? = nil) {
        guard presentsNativePanels else { return }
        guard let anchor = testFieldPanelAnchor else { hidePanel(); return }
        let callbackToken = UUID().uuidString
        candidateCallbackToken = correctionMessage == nil ? callbackToken : nil
        toneCallbackToken = nil
        panelController.show(
            selection: selection,
            sessionToken: callbackToken,
            anchorRect: anchor.rect,
            visibleScreenFrame: anchor.screen,
            visibleRowCount: visibleRowCount,
            size: pickerSize,
            appearance: panelAppearance,
            correctionMessage: correctionMessage
        )
    }

    private func showSkinTonePanel(_ selection: SkinToneSelection) {
        guard presentsNativePanels else { return }
        guard let anchor = testFieldPanelAnchor else { hidePanel(); return }
        let callbackToken = UUID().uuidString
        toneCallbackToken = callbackToken
        candidateCallbackToken = nil
        skinTonePanelController.show(
            selection: selection,
            sessionToken: callbackToken,
            anchorRect: anchor.rect,
            visibleScreenFrame: anchor.screen,
            appearance: panelAppearance
        )
    }

    private func persistSuccessfulToneCommit(_ request: CommitRequest) {
        guard request.trigger == .skinTone,
              let store
        else {
            return
        }

        tonePreferenceWriteGeneration += 1
        persistedReloadGeneration += 1
        let generation = tonePreferenceWriteGeneration
        let previousWrite = tonePreferenceWriteTask
        tonePreferenceWriteInFlight = true
        searchIndexPending = true
        hidePanel()
        tonePreferenceWriteTask = Task { [weak self] in
            await previousWrite?.value
            do {
                let preferences = try await Task.detached(priority: .utility) {
                    try store.recordSkinTonePreference(
                        emojiID: request.candidate.id,
                        selectedVariant: request.renderedEmoji,
                        commitSucceeded: true
                    )
                    return try store.currentSkinTonePreferences()
                }.value
                guard let self, self.tonePreferenceWriteGeneration == generation else {
                    return
                }
                self.tonePreferenceWriteInFlight = false
                self.skinTonePreferencesSnapshot = preferences
                self.scheduleSearchEngineRebuild()
                self.updateAutocomplete()
            } catch {
                guard let self, self.tonePreferenceWriteGeneration == generation else {
                    return
                }
                self.tonePreferenceWriteInFlight = false
                self.clearSearchIndexPendingIfStable()
                self.updateAutocomplete()
                self.statusMessage = "The skin-tone preference could not be saved."
            }
        }
    }

    private func replaceTestFieldToken(with request: CommitRequest) -> Bool {
        let text = tokenText as NSString
        let range = request.context.replacementRange
        let detection = tokenDetection
        guard testFieldHasSelectedText == false,
              range.location >= 0,
              NSMaxRange(range) <= text.length,
              detection.replacementRange == range,
              detection.normalizedQuery == request.context.normalizedQuery,
              (detection.state == .activeQuery || detection.state == .closingColonIntent)
        else {
            statusMessage = "The test field token changed before it could be replaced."
            _ = stateMachine.handle(.commitCompleted)
            return false
        }
        let replacement = NSMutableString(string: tokenText)
        replacement.replaceCharacters(in: range, with: request.renderedEmoji)
        let caretOffset = range.location + (request.renderedEmoji as NSString).length
        tokenText = replacement as String
        testFieldCaretUTF16Offset = caretOffset
        testFieldHasSelectedText = false
        testFieldSelectionText = tokenText
        testFieldCaretRequest += 1
        updateAutocomplete()
        _ = stateMachine.handle(.commitCompleted)
        return true
    }

    private func enqueueCustomTagMutation(
        clearInputIfMatches input: String? = nil,
        failureMessage: String = "The custom tag could not be saved.",
        operation: @escaping @Sendable (ColonLocalStore) throws -> Void
    ) {
        guard let store else {
            statusMessage = "Settings are temporarily unavailable."
            return
        }

        customTagMutationGeneration += 1
        persistedReloadGeneration += 1
        let generation = customTagMutationGeneration
        let previousMutation = customTagMutationTask
        customTagMutationInFlight = true
        searchIndexPending = true
        hidePanel()
        customTagMutationTask = Task { [weak self] in
            await previousMutation?.value
            do {
                let state = try await Task.detached(priority: .utility) {
                    () throws -> CustomTagSearchState in
                    try operation(store)
                    return CustomTagSearchState(
                        customTags: try store.currentCustomTags(),
                        skinTonePreferences: try store.currentSkinTonePreferences()
                    )
                }.value
                guard let self, self.customTagMutationGeneration == generation else {
                    return
                }
                self.customTagsSnapshot = state.customTags
                self.skinTonePreferencesSnapshot = state.skinTonePreferences
                self.customTagMutationInFlight = false
                self.searchIndexPending = true
                if let input, self.customTagInput == input {
                    self.customTagInput = ""
                }
                self.statusMessage = nil
                self.scheduleSearchEngineRebuild()
                self.updateAutocomplete()
            } catch {
                guard let self, self.customTagMutationGeneration == generation else {
                    return
                }
                self.customTagMutationInFlight = false
                self.clearSearchIndexPendingIfStable()
                self.updateAutocomplete()
                if let mutationError = error as? CustomTagMutationError {
                    switch mutationError {
                    case .empty:
                        self.statusMessage = "Enter a tag before adding it."
                    case .invalidCharacters:
                        self.statusMessage = "Tags may contain letters, digits, _, +, and - only."
                    case .duplicate:
                        self.statusMessage = "That emoji already has this tag."
                    }
                } else {
                    self.statusMessage = failureMessage
                }
            }
        }
    }

    private func scheduleSearchEngineRebuild() {
        guard let dataset = emojiDataset else {
            return
        }
        searchEngineBuildGeneration += 1
        let generation = searchEngineBuildGeneration
        let customTags = customTagsSnapshot
        let skinTonePreferences = skinTonePreferencesSnapshot
        searchEngineBuildInFlight = true
        searchEngineBuildTask = Task { [weak self] in
            let engine = await Task.detached(priority: .utility) {
                EmojiSearchEngine(
                    dataset: dataset,
                    customTags: customTags,
                    skinTonePreferences: skinTonePreferences
                )
            }.value
            guard let self, self.searchEngineBuildGeneration == generation else {
                return
            }
            self.searchEngine = engine
            self.searchEngineBuildInFlight = false
            self.clearSearchIndexPendingIfStable()
            self.updateAutocomplete()
        }
    }

    private func clearSearchIndexPendingIfStable() {
        guard customTagMutationInFlight == false,
              persistedReloadPending == false,
              tonePreferenceWriteInFlight == false,
              searchEngineBuildInFlight == false
        else {
            return
        }
        searchIndexPending = false
    }

    private func persistSettings(
        _ mutation: @escaping @Sendable (inout ColonSettingsSnapshot) -> Void
    ) {
        guard let store else {
            statusMessage = "Settings are temporarily unavailable."
            return
        }

        var optimistic = currentSettingsSnapshot
        mutation(&optimistic)
        applySettings(optimistic, refreshPanel: false)
        updateAutocomplete()
        statusMessage = nil

        settingsWriteGeneration += 1
        persistedReloadGeneration += 1
        let generation = settingsWriteGeneration
        let previousWrite = settingsWriteTask
        settingsWriteTask = Task { [weak self] in
            await previousWrite?.value
            let writtenSnapshot = await Task.detached(priority: .utility) { () -> ColonSettingsSnapshot? in
                do {
                    try store.update(mutation)
                    return try store.currentSnapshot()
                } catch {
                    return nil
                }
            }.value
            guard let self, self.settingsWriteGeneration == generation else {
                return
            }
            if let writtenSnapshot {
                self.applySettings(writtenSnapshot, refreshPanel: false)
                self.updateAutocomplete()
                self.statusMessage = nil
            } else {
                let storedSnapshot = await Task.detached(priority: .utility) {
                    try? store.currentSnapshot()
                }.value
                if let storedSnapshot {
                    self.applySettings(storedSnapshot, refreshPanel: false)
                    self.updateAutocomplete()
                }
                self.statusMessage = "The setting could not be saved."
            }
        }
    }

    private var settingsWriteGeneration = 0

    private func applySettings(
        _ snapshot: ColonSettingsSnapshot,
        refreshPanel shouldRefreshPanel: Bool = true
    ) {
        currentSettingsSnapshot = snapshot
        isEnabled = snapshot.isEnabled
        launchAtLoginPreferred = snapshot.launchAtLoginPreferred
        menuBarVisible = snapshot.menuBarVisible
        appearancePreference = snapshot.appearance
        pickerSizePreference = snapshot.pickerSize
        visibleRows = snapshot.visibleRowCount
        maximumResults = snapshot.maximumResultCount
        enabledApps = snapshot.enabledApps
        maximumResultCount = snapshot.maximumResultCount
        visibleRowCount = snapshot.visibleRowCount
        pickerSize = snapshot.pickerSize
        panelAppearance = switch snapshot.appearance {
        case .system: .system
        case .light: .light
        case .dark: .dark
        }
        if shouldRefreshPanel {
            refreshPanel()
        }
    }

    private func applyInitialPersistedState(
        _ initial: InitialPersistedState,
        appliesSettings: Bool,
        appliesCustomTags: Bool,
        appliesSkinTonePreferences: Bool
    ) {
        if appliesSettings {
            currentSettingsSnapshot = initial.state.settings
            applySettings(initial.state.settings, refreshPanel: false)
        }
        if appliesCustomTags {
            customTagsSnapshot = initial.state.customTags
        }
        if appliesSkinTonePreferences {
            skinTonePreferencesSnapshot = initial.state.skinTonePreferences
        }
        if initial.recoveredDamagedFile, statusMessage == nil {
            statusMessage = "Recovered settings from a damaged local file."
        }
        updateAutocomplete()
    }

    func reloadPersistedState() {
        guard let store else {
            return
        }
        persistedReloadGeneration += 1
        let generation = persistedReloadGeneration
        persistedReloadRequestGeneration += 1
        let requestGeneration = persistedReloadRequestGeneration
        let pendingSettingsWrite = settingsWriteTask
        let pendingToneWrite = tonePreferenceWriteTask
        let pendingTagMutation = customTagMutationTask
        persistedReloadPending = true
        searchIndexPending = true
        hidePanel()
        updateAutocomplete()
        persistedReloadTask = Task { [weak self] in
            await pendingSettingsWrite?.value
            await pendingToneWrite?.value
            await pendingTagMutation?.value
            do {
                let state = try await Task.detached(priority: .utility) {
                    () throws -> PersistedCompanionState in
                    PersistedCompanionState(
                        settings: try store.currentSnapshot(),
                        customTags: try store.currentCustomTags(),
                        skinTonePreferences: try store.currentSkinTonePreferences()
                    )
                }.value
                guard let self,
                      self.persistedReloadRequestGeneration == requestGeneration
                else {
                    return
                }
                guard self.persistedReloadGeneration == generation else {
                    self.reloadPersistedState()
                    return
                }
                let searchIndexChanged = self.customTagsSnapshot != state.customTags
                    || self.skinTonePreferencesSnapshot != state.skinTonePreferences
                self.customTagsSnapshot = state.customTags
                self.skinTonePreferencesSnapshot = state.skinTonePreferences
                self.applySettings(state.settings, refreshPanel: false)
                self.persistedReloadPending = false
                if searchIndexChanged {
                    self.searchIndexPending = true
                    self.scheduleSearchEngineRebuild()
                } else {
                    self.clearSearchIndexPendingIfStable()
                    self.updateAutocomplete()
                }
                self.statusMessage = nil
            } catch {
                guard let self,
                      self.persistedReloadRequestGeneration == requestGeneration
                else {
                    return
                }
                guard self.persistedReloadGeneration == generation else {
                    self.reloadPersistedState()
                    return
                }
                self.persistedReloadPending = false
                self.clearSearchIndexPendingIfStable()
                self.updateAutocomplete()
                self.statusMessage = "Updated settings could not be reloaded."
            }
        }
    }

    private func applyEmojiBrowserLoad(_ result: EmojiBrowserLoadResult) {
        emojiDataset = result.dataset
        emojiBrowserRows = result.rows
        selectedEmojiID = selectedEmojiID ?? result.rows.first?.id
        datasetSummary = result.summary
        scheduleSearchEngineRebuild()
    }
}

private extension EmojiTokenState {
    var displayName: String {
        switch self {
        case .inactive:
            "Inactive"
        case .colonOnly:
            "Colon only"
        case .activeQuery:
            "Active query"
        case .closingColonIntent:
            "Closing-colon intent"
        case .terminatedOrInvalid:
            "Terminated or invalid"
        }
    }
}

@MainActor
struct BuildInformationView: View {
    @ObservedObject var viewModel: BuildInformationViewModel

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Local"
    }

    var body: some View {
        CompanionSettingsView(viewModel: viewModel, version: version, build: build)
        .preferredColorScheme(viewModel.preferredColorScheme)
        .onDisappear {
            viewModel.hidePanel()
        }
    }
}
