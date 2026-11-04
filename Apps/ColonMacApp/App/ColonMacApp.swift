import AppKit
import SwiftUI

@main
struct ColonMacApp: App {
    @StateObject private var viewModel = BuildInformationViewModel()

    var body: some Scene {
        Window("Colon", id: "settings") {
            BuildInformationView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)

        MenuBarExtra(
            "Colon",
            systemImage: "coloncurrencysign.circle.fill",
            isInserted: Binding(
                get: { viewModel.menuBarVisible },
                set: { viewModel.setMenuBarVisible($0) }
            )
        ) {
            CompanionMenuBarContent(viewModel: viewModel)
        }
    }
}

private struct CompanionMenuBarContent: View {
    @ObservedObject var viewModel: BuildInformationViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Settings") {
            openWindow(id: "settings")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button(viewModel.isEnabled ? "Disable Colon" : "Enable Colon") {
            viewModel.setEnabled(viewModel.isEnabled == false)
        }
        Button("Test Colon") {
            viewModel.requestTestFieldFocus()
            openWindow(id: "settings")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit Companion App") {
            NSApplication.shared.terminate(nil)
        }
    }
}
