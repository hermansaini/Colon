import AppKit
import ColonModels
import ColonSettingsCore
import Foundation
import Testing
import SwiftUI
@testable import ColonCompanion

private struct NoTestNotifications: SettingsChangePosting {
    func postSettingsChanged() {}
}

@Suite(.serialized)
@MainActor
struct CompanionModelTests {
    private func makeModel() -> (BuildInformationViewModel, ColonStoragePaths) {
        _ = NSApplication.shared
        let paths = ColonStoragePaths(rootDirectoryURL:
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        return (BuildInformationViewModel(storagePaths: paths, startsSystemServices: false), paths)
    }

    private func setText(_ text: String, in model: BuildInformationViewModel) {
        model.tokenText = text
        let end = model.tokenText.endIndex
        model.testFieldSelectionChanged(TextSelection(range: end..<end))
    }

    @Test func nativeFieldTabCyclesTonesWithoutLeavingTheField() async throws {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        model.testFieldFocusChanged(true)
        let editor = NSTextView()
        editor.string = ":wave"
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        let coordinator = CompanionTextField.Coordinator(viewModel: model)
        let tab = NSSelectorFromString("insertTab:")
        #expect(coordinator.handleCommand(tab, modifiers: [], editor: editor))
        let firstTone = model.interactionStatus
        #expect(firstTone.hasPrefix("Skin tones"))
        #expect(coordinator.handleCommand(tab, modifiers: [], editor: editor))
        #expect(model.interactionStatus != firstTone)
        #expect(editor.string == ":wave")
        #expect(coordinator.handleCommand(tab, modifiers: [.shift], editor: editor) == false)
        #expect(coordinator.handleCommand(NSSelectorFromString("insertNewline:"), modifiers: [], editor: editor))
        #expect(editor.string == model.tokenText)
        #expect(editor.string == "👋🏼")
        await model.waitForPendingSettingsWrites()
        model.testFieldFocusChanged(false)
    }

    @Test func unavailableNativeCaretDoesNotConsumeKeysOrCommitClosingColon() async {
        _ = NSApplication.shared
        let paths = ColonStoragePaths(rootDirectoryURL:
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        let model = BuildInformationViewModel(storagePaths: paths, startsSystemServices: false,
                                              presentsNativePanels: true)
        await model.waitForInitialLoad()
        model.testFieldFocusChanged(true)
        model.testFieldEdited(text: ":wave", selection: NSRange(location: 5, length: 0), caretRect: .zero)
        #expect(model.handleTestFieldKey(.tab) == false)
        #expect(model.handleTestFieldKey(.enter) == false)
        model.testFieldEdited(text: ":wave:", selection: NSRange(location: 6, length: 0), caretRect: .zero)
        #expect(model.tokenText == ":wave:")
        #expect(model.interactionStatus == "Caret position unavailable")
        model.testFieldFocusChanged(false)
    }

    @Test func nativeEditsKeepCorrectionVisibleAndCannotCommitStaleRows() async {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        model.testFieldFocusChanged(true)
        func edit(_ text: String) {
            model.testFieldEdited(text: text,
                selection: NSRange(location: (text as NSString).length, length: 0),
                caretRect: NSRect(x: 400, y: 300, width: 1, height: 20))
        }
        edit(":fire")
        #expect(model.interactionStatus.hasPrefix("Candidates"))
        edit(":firezzzzzz")
        #expect(model.interactionStatus == "Correcting shortcode")
        #expect(model.handleTestFieldKey(.enter) == false)
        #expect(model.handleTestFieldKey(.tab) == false)
        edit(":")
        #expect(model.interactionStatus == "Correcting shortcode")
        edit(":wave")
        #expect(model.handleTestFieldKey(.tab))
        edit(":wave") // duplicate native selection notification must not reset tones
        #expect(model.interactionStatus.hasPrefix("Skin tones"))
        #expect(model.handleTestFieldKey(.enter))
        #expect(model.tokenText == "👋🏻")
        await model.waitForPendingSettingsWrites()
        model.testFieldFocusChanged(false)
    }

    @Test func initialLoadKeepsUnfocusedPlaygroundIdle() async throws {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        #expect(model.emojiBrowserRows.count > 1_000)
        #expect(model.interactionStatus == "Idle")
        #expect(model.statusMessage == nil)
        #expect(model.isEnabled)
    }

    @Test func rapidSettingsChangesPersistInOrder() async throws {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        for index in 0..<20 {
            model.setEnabled(index % 2 == 0)
            model.setMenuBarVisible(index % 2 != 0)
        }
        model.setAppearance(.dark)
        model.setVisibleRows(8)
        model.setMaximumResults(75)
        await model.waitForPendingSettingsWrites()
        let saved = try ColonLocalStore(paths: paths).currentSnapshot()
        #expect(saved.isEnabled == false)
        #expect(saved.menuBarVisible == true)
        #expect(saved.appearance == .dark)
        #expect(saved.visibleRowCount == 8)
        #expect(saved.maximumResultCount == 75)
        #expect(model.isEnabled == saved.isEnabled)
        #expect(model.statusMessage == nil)
    }

    @Test func resultCountAlwaysAccommodatesVisibleRows() async throws {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        model.setMaximumResults(6)
        model.setVisibleRows(12)
        await model.waitForPendingSettingsWrites()
        let saved = try ColonLocalStore(paths: paths).currentSnapshot()
        #expect(saved.maximumResultCount >= saved.visibleRowCount)
        #expect(model.maximumResults >= model.visibleRows)
        #expect(model.statusMessage == nil)
    }

    @Test func enterAndClosingColonReplaceTheFocusedToken() async {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        model.testFieldFocusChanged(true)
        setText("hello :fire", in: model)
        #expect(model.handleTestFieldKey(.enter))
        #expect(model.tokenText == "hello 🔥")
        setText("hello :fire:", in: model)
        #expect(model.tokenText == "hello 🔥")
        model.testFieldFocusChanged(false)
    }

    @Test func losingFocusOrDisablingColonPreventsCommits() async {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        model.testFieldFocusChanged(true)
        setText(":fire", in: model)
        model.testFieldFocusChanged(false)
        #expect(model.handleTestFieldKey(.enter) == false)
        #expect(model.tokenText == ":fire")
        model.testFieldFocusChanged(true)
        model.setEnabled(false)
        #expect(model.handleTestFieldKey(.enter) == false)
        #expect(model.tokenText == ":fire")
        await model.waitForPendingSettingsWrites()
    }

    @Test func escapeSuppressesFurtherQueryEditsUntilBoundary() async {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        model.testFieldFocusChanged(true)
        setText(":fire", in: model)
        #expect(model.handleTestFieldKey(.escape))
        setText(":firew", in: model)
        #expect(model.handleTestFieldKey(.enter) == false)
        #expect(model.tokenText == ":firew")
        setText("hello ", in: model)
        setText("hello :fire", in: model)
        #expect(model.handleTestFieldKey(.enter))
        #expect(model.tokenText == "hello 🔥")
        model.testFieldFocusChanged(false)
    }


    @Test func insertionAtCaretPreservesTrailingTextAndUnicodePrefix() async {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        model.testFieldFocusChanged(true)
        setText("🙂 lead :fire tail", in: model)
        let caret = model.tokenText.range(of: ":fire")!.upperBound
        model.testFieldSelectionChanged(TextSelection(range: caret..<caret))
        #expect(model.handleTestFieldKey(.enter))
        #expect(model.tokenText == "🙂 lead 🔥 tail")
        model.testFieldFocusChanged(false)
    }

    @Test func selectedTextCannotCommitATrailingShortcode() async {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        model.testFieldFocusChanged(true)
        setText("lead :fire", in: model)
        let selected = model.tokenText.range(of: "lead")!
        model.testFieldSelectionChanged(TextSelection(range: selected))
        #expect(model.handleTestFieldKey(.enter) == false)
        #expect(model.tokenText == "lead :fire")
        let start = model.tokenText.startIndex
        model.testFieldSelectionChanged(TextSelection(range: start..<start))
        #expect(model.handleTestFieldKey(.enter) == false)
        #expect(model.tokenText == "lead :fire")
        model.testFieldFocusChanged(false)
    }


    @Test func staleSelectionCannotConsumeEnterOrCrash() async {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        model.testFieldFocusChanged(true)
        setText(":fire", in: model)
        model.tokenText = ":wave"
        #expect(model.handleTestFieldKey(.enter) == false)
        #expect(model.tokenText == ":wave")
        let oldText = String(repeating: "x", count: 300)
        model.testFieldSelectionChanged(TextSelection(insertionPoint: oldText.endIndex))
        #expect(model.handleTestFieldKey(.enter) == false)
        #expect(model.tokenText == ":wave")
        model.testFieldFocusChanged(false)
    }


    @Test func rapidToneCommitsKeepLatestPreferenceAndCustomTags() async throws {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        model.testFieldFocusChanged(true)
        setText(":wave", in: model)
        #expect(model.handleTestFieldKey(.tab))
        #expect(model.handleTestFieldKey(.enter))
        let firstTone = model.tokenText
        await model.waitForPendingSettingsWrites()
        setText(":wave", in: model)
        #expect(model.handleTestFieldKey(.tab))
        #expect(model.handleTestFieldKey(.tab))
        #expect(model.handleTestFieldKey(.enter))
        let lastTone = model.tokenText
        #expect(firstTone != lastTone)
        let wave = try #require(model.emojiBrowserRows.first { $0.emoji == "👋" })
        model.selectedEmojiID = wave.id
        model.customTagInput = "race_wave_tag"
        model.addCustomTag()
        await model.waitForPendingSettingsWrites()
        let saved = try ColonLocalStore(paths: paths).currentSkinTonePreferences()
        #expect(saved.preferences.first { $0.emojiID == wave.id }?.selectedVariant == lastTone)
        setText(":race_wave_tag", in: model)
        #expect(model.handleTestFieldKey(.enter))
        #expect(model.tokenText == lastTone)
        model.testFieldFocusChanged(false)
    }

    @Test func localToneWriteBlocksEnterUntilSearchIndexIsUpdated() async throws {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        model.testFieldFocusChanged(true)
        setText(":wave", in: model)
        #expect(model.handleTestFieldKey(.tab))
        #expect(model.handleTestFieldKey(.enter))
        let selectedTone = model.tokenText

        setText(":wave", in: model)
        #expect(model.handleTestFieldKey(.enter) == false)
        #expect(model.tokenText == ":wave")

        await model.waitForPendingSettingsWrites()
        setText(":wave", in: model)
        #expect(model.handleTestFieldKey(.enter))
        #expect(model.tokenText == selectedTone)
        model.testFieldFocusChanged(false)
    }

    @Test func externalToneOnlyReloadBlocksEnterUntilSearchIndexIsUpdated() async throws {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        let wave = try #require(model.emojiBrowserRows.first { $0.emoji == "👋" })
        let externalStore = try ColonLocalStore(paths: paths, changePoster: NoTestNotifications())
        try externalStore.recordSkinTonePreference(
            emojiID: wave.id,
            selectedVariant: "👋🏽",
            commitSucceeded: true
        )
        model.testFieldFocusChanged(true)
        model.reloadPersistedState()

        setText(":wave", in: model)
        #expect(model.handleTestFieldKey(.enter) == false)
        #expect(model.tokenText == ":wave")

        await model.waitForPendingSettingsWrites()
        setText(":wave", in: model)
        #expect(model.handleTestFieldKey(.enter))
        #expect(model.tokenText == "👋🏽")
        model.testFieldFocusChanged(false)
    }

    @Test func cancellingTonePickerDoesNotPersistAPreference() async throws {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        model.testFieldFocusChanged(true)
        setText(":wave", in: model)
        #expect(model.handleTestFieldKey(.tab))
        #expect(model.handleTestFieldKey(.escape))
        await model.waitForPendingSettingsWrites()
        #expect(model.tokenText == ":wave")
        #expect(try ColonLocalStore(paths: paths).currentSkinTonePreferences().preferences.isEmpty)
        model.testFieldFocusChanged(false)
    }


    @Test func customTagsAddAndRemoveFromLiveSearch() async throws {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        let fire = try #require(model.emojiBrowserRows.first { $0.emoji == "🔥" })
        model.selectedEmojiID = fire.id
        model.customTagInput = "local_fire_test"
        model.addCustomTag()
        await model.waitForPendingSettingsWrites()
        #expect(model.statusMessage == nil)
        model.testFieldFocusChanged(true)
        setText(":local_fire_test", in: model)
        #expect(model.handleTestFieldKey(.enter))
        #expect(model.tokenText == "🔥")
        let saved = try ColonLocalStore(paths: paths).currentCustomTags()
        let tag = try #require(saved.records.first { $0.normalizedTag == "local_fire_test" })
        model.removeCustomTag(id: tag.id)
        await model.waitForPendingSettingsWrites()
        setText(":local_fire_test", in: model)
        #expect(model.handleTestFieldKey(.enter) == false)
        #expect(model.tokenText == ":local_fire_test")
        #expect(model.statusMessage == nil)
        model.testFieldFocusChanged(false)
    }


    @Test func externalTagReloadSurvivesConcurrentLocalSetting() async throws {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        await model.waitForInitialLoad()
        let fire = try #require(model.emojiBrowserRows.first { $0.emoji == "🔥" })
        let externalStore = try ColonLocalStore(paths: paths, changePoster: NoTestNotifications())
        _ = try externalStore.addCustomTag(emojiID: fire.id, tag: "external_fire_test")
        model.reloadPersistedState()
        model.setAppearance(.dark)
        await model.waitForPendingSettingsWrites()
        #expect(model.appearancePreference == .dark)
        model.testFieldFocusChanged(true)
        setText(":external_fire_test", in: model)
        #expect(model.handleTestFieldKey(.enter))
        #expect(model.tokenText == "🔥")
        model.testFieldFocusChanged(false)
    }


    @Test func startupLoadDoesNotOverwriteAnImmediatePreferenceChange() async throws {
        let (model, paths) = makeModel()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        model.setEnabled(false)
        model.setMenuBarVisible(false)
        await model.waitForInitialLoad()
        await model.waitForPendingSettingsWrites()
        #expect(model.isEnabled == false)
        #expect(model.menuBarVisible == false)
        let saved = try ColonLocalStore(paths: paths).currentSnapshot()
        #expect(saved.isEnabled == false)
        #expect(saved.menuBarVisible == false)
    }

    @Test func startupLoadPreservesExistingTagsAndTonesDuringImmediateSettingChange() async throws {
        _ = NSApplication.shared
        let paths = ColonStoragePaths(rootDirectoryURL:
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        defer { try? FileManager.default.removeItem(at: paths.rootDirectoryURL) }
        let waveID = EmojiID(rawValue: "1f44b")
        let seedStore = try ColonLocalStore(paths: paths, changePoster: NoTestNotifications())
        _ = try seedStore.addCustomTag(emojiID: waveID, tag: "startup_wave_seed")
        try seedStore.recordSkinTonePreference(
            emojiID: waveID,
            selectedVariant: "👋🏽",
            commitSucceeded: true
        )

        let model = BuildInformationViewModel(storagePaths: paths, startsSystemServices: false)
        model.setAppearance(.dark)
        await model.waitForInitialLoad()
        await model.waitForPendingSettingsWrites()

        #expect(model.appearancePreference == .dark)
        model.selectedEmojiID = waveID
        #expect(model.selectedEmojiTags.map(\.normalizedTag) == ["startup_wave_seed"])
        model.testFieldFocusChanged(true)
        setText(":startup_wave_seed", in: model)
        #expect(model.handleTestFieldKey(.enter))
        #expect(model.tokenText == "👋🏽")
        model.testFieldFocusChanged(false)
    }

}
