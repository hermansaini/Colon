import AppKit
import ColonModels
import SwiftUI

enum CompanionSettingsTab: Hashable {
    case general
    case applications
    case appearance
    case emojiTags
    case privacy
    case diagnostics
    case about
}

/// Matches the two-dot mark and indigo background of ColonAppIcon.svg.
private struct ColonLogo: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 220 / 864)
                .fill(Color(red: 79 / 255.0, green: 70 / 255.0, blue: 229 / 255.0))
            VStack(spacing: size * 120 / 864) {
                Circle().frame(width: size * 192 / 864, height: size * 192 / 864)
                Circle().frame(width: size * 192 / 864, height: size * 192 / 864)
            }
            .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Colon logo")
    }
}

@MainActor
struct CompanionSettingsView: View {
    @ObservedObject var viewModel: BuildInformationViewModel
    let version: String
    let build: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ColonLogo(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Colon")
                        .font(.title.bold())
                    Text("Native emoji shortcode autocomplete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("macOS 26+", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            TabView(selection: $viewModel.selectedSettingsSection) {
                GeneralSettingsSection(viewModel: viewModel)
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(CompanionSettingsTab.general)
                ApplicationSettingsSection(viewModel: viewModel)
                    .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
                    .tag(CompanionSettingsTab.applications)
                AppearanceSettingsSection(viewModel: viewModel)
                    .tabItem { Label("Appearance", systemImage: "paintbrush") }
                    .tag(CompanionSettingsTab.appearance)
                EmojiTagsSettingsSection(viewModel: viewModel)
                    .tabItem { Label("Emoji Tags", systemImage: "tag") }
                    .tag(CompanionSettingsTab.emojiTags)
                PrivacySettingsSection()
                    .tabItem { Label("Privacy", systemImage: "hand.raised") }
                    .tag(CompanionSettingsTab.privacy)
                DiagnosticsSettingsSection(viewModel: viewModel)
                    .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                    .tag(CompanionSettingsTab.diagnostics)
                AboutSettingsSection(version: version, build: build)
                    .tabItem { Label("About", systemImage: "info.circle") }
                    .tag(CompanionSettingsTab.about)
            }

            if let statusMessage = viewModel.statusMessage {
                Label(statusMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 780, height: 650)
    }
}

@MainActor
private struct GeneralSettingsSection: View {
    @ObservedObject var viewModel: BuildInformationViewModel
    @State private var confirmsUninstall = false

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Enable Colon",
                    isOn: Binding(
                        get: { viewModel.isEnabled },
                        set: { viewModel.setEnabled($0) }
                    )
                )
                Toggle(
                    "Launch companion app at login",
                    isOn: Binding(
                        get: { viewModel.launchAtLoginPreferred },
                        set: { viewModel.setLaunchAtLoginPreferred($0) }
                    )
                )
                Toggle(
                    "Show Colon in the menu bar",
                    isOn: Binding(
                        get: { viewModel.menuBarVisible },
                        set: { viewModel.setMenuBarVisible($0) }
                    )
                )
                LabeledContent("Launch status") {
                    Text(viewModel.launchAtLoginStatus)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Input method") {
                    Text(viewModel.inputMethodStatus)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if viewModel.inputMethodInstallationLocation == .notInstalled {
                        Button("Install Input Method") {
                            viewModel.installInputMethod()
                        }
                    } else if viewModel.inputMethodInstallationLocation != .multipleCopies,
                              viewModel.inputMethodStage != .ready {
                        Button("Enable & Select") {
                            viewModel.enableAndSelectInputMethod()
                        }
                    }
                    Button("Refresh") {
                        viewModel.refreshInputMethodReadiness()
                    }
                    if viewModel.inputMethodInstallationLocation == .userLibrary {
                        Button("Uninstall", role: .destructive) {
                            confirmsUninstall = true
                        }
                    }
                }
                if viewModel.inputMethodRequiresLogout {
                    Text("Log out and back in if macOS does not discover Colon after installation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if viewModel.inputMethodInstallationLocation == .systemLibrary
                    || viewModel.inputMethodInstallationLocation == .managedElsewhere
                {
                    Text("This installation is managed outside your account. Ask its administrator to update or remove it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if viewModel.inputMethodInstallationLocation == .multipleCopies {
                    Text("Multiple copies share the Colon input-source identifier. Remove the duplicate through its administrator.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("If automatic enablement is unavailable, open System Settings → Keyboard → Text Input → Edit and add Colon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Try Colon") {
                CompanionTextField(viewModel: viewModel)
                    .frame(height: 26)

                Text("Type a colon and an emoji name. Use ↑ and ↓ to choose, Enter to insert, Tab for skin tones, and Escape to dismiss.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(viewModel.interactionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog(
            "Uninstall the Colon input method?",
            isPresented: $confirmsUninstall,
            titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) {
                viewModel.uninstallInputMethod()
            }
            Button("Cancel", role: .cancel) {}
        }
    }


}

@MainActor
private struct ApplicationSettingsSection: View {
    @ObservedObject var viewModel: BuildInformationViewModel

    var body: some View {
        Form {
            Section {
                ForEach(SupportedApplication.allCases) { application in
                    Toggle(
                        application.displayName,
                        isOn: Binding(
                            get: { viewModel.enabledApps[application.rawValue] ?? false },
                            set: { viewModel.setApplication(application, enabled: $0) }
                        )
                    )
                }
            } header: {
                Text("Supported Applications")
            } footer: {
                Text("Colon remains inactive in applications disabled here.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

@MainActor
private struct AppearanceSettingsSection: View {
    @ObservedObject var viewModel: BuildInformationViewModel

    var body: some View {
        Form {
            Section("Appearance") {
                Picker(
                    "Color scheme",
                    selection: Binding(
                        get: { viewModel.appearancePreference },
                        set: { viewModel.setAppearance($0) }
                    )
                ) {
                    Text("System").tag(AppearancePreference.system)
                    Text("Light").tag(AppearancePreference.light)
                    Text("Dark").tag(AppearancePreference.dark)
                }
                .pickerStyle(.segmented)

                Picker(
                    "Picker size",
                    selection: Binding(
                        get: { viewModel.pickerSizePreference },
                        set: { viewModel.setPickerSize($0) }
                    )
                ) {
                    Text("Compact").tag(PickerSize.compact)
                    Text("Standard").tag(PickerSize.standard)
                    Text("Large").tag(PickerSize.large)
                }
                .pickerStyle(.segmented)

                Stepper(
                    "Visible rows: \(viewModel.visibleRows)",
                    value: Binding(
                        get: { viewModel.visibleRows },
                        set: { viewModel.setVisibleRows($0) }
                    ),
                    in: 1...12
                )
                Stepper(
                    "Maximum results: \(viewModel.maximumResults)",
                    value: Binding(
                        get: { viewModel.maximumResults },
                        set: { viewModel.setMaximumResults($0) }
                    ),
                    in: viewModel.visibleRows...100
                )
            }


        }
        .formStyle(.grouped)
        .padding()
    }
}

@MainActor
private struct EmojiTagsSettingsSection: View {
    @ObservedObject var viewModel: BuildInformationViewModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search emoji", text: $viewModel.emojiBrowserQuery)
                    .textFieldStyle(.roundedBorder)
                List(viewModel.visibleEmojiBrowserRows, selection: $viewModel.selectedEmojiID) { row in
                    HStack {
                        Text(row.emoji)
                        VStack(alignment: .leading) {
                            Text(row.canonicalName)
                            Text(":\(row.canonicalAlias)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(row.id)
                }
            }
            .frame(minWidth: 330)

            VStack(alignment: .leading, spacing: 12) {
                if let emoji = viewModel.selectedEmoji {
                    HStack {
                        Text(emoji.emoji)
                            .font(.system(size: 42))
                        VStack(alignment: .leading) {
                            Text(emoji.canonicalName)
                                .font(.headline)
                            Text(":\(emoji.canonicalAlias)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        TextField("letters, digits, _, +, -", text: $viewModel.customTagInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { viewModel.addCustomTag() }
                        Button("Add") { viewModel.addCustomTag() }
                    }

                    List(viewModel.selectedEmojiTags) { tag in
                        HStack {
                            Text(tag.normalizedTag)
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.removeCustomTag(id: tag.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } else {
                    ContentUnavailableView("Select an Emoji", systemImage: "face.smiling")
                }
            }
            .padding(.leading, 12)
            .frame(minWidth: 330)
        }
        .padding()
    }
}

private struct PrivacySettingsSection: View {
    var body: some View {
        Form {
            Section("Local by Design") {
                Label("No telemetry or analytics", systemImage: "checkmark.shield")
                Label("No accounts", systemImage: "person.crop.circle.badge.xmark")
                Label("No runtime network access", systemImage: "network.slash")
                Text("Colon reads only the minimal text context needed to detect an active shortcode. Context snapshots are processed in memory and not retained.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

@MainActor
private struct DiagnosticsSettingsSection: View {
    @ObservedObject var viewModel: BuildInformationViewModel

    var body: some View {
        Form {
            Section("Dataset") {
                Text(viewModel.datasetSummary)
                LabeledContent("Storage") {
                    Text("~/Library/Application Support/Colon")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Input Method") {
                LabeledContent("Installation") { Text(viewModel.inputMethodStatus) }
                Button("Export Redacted Diagnostics") {
                    viewModel.exportDiagnostics()
                }
                Text("Exports versions, readiness state, and allowlisted error codes only. Typed text and queries are never included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AboutSettingsSection: View {
    let version: String
    let build: String

    var body: some View {
        VStack(spacing: 16) {
            ColonLogo(size: 80)
            Text("Colon")
                .font(.largeTitle.bold())
            Text("Version \(version) (\(build))")
                .foregroundStyle(.secondary)
            Text("Development preview for macOS 26 and later")
            Button("View Licenses") {
                if let resources = Bundle.main.resourceURL {
                    NSWorkspace.shared.open(resources.appending(path: "Licenses", directoryHint: .isDirectory))
                }
            }
            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
