import AppKit
import InputMethodKit
import OSLog

@main
enum ColonInputMethodMain {
    private static let logger = Logger(
        subsystem: "org.colonproject.inputmethod.Colon",
        category: "lifecycle"
    )

    static func main() {
        let bundle = Bundle.main
        guard let connectionName = bundle.object(
            forInfoDictionaryKey: "InputMethodConnectionName"
        ) as? String,
              let bundleIdentifier = bundle.bundleIdentifier
        else {
            logger.fault("event=server_configuration_invalid")
            return
        }

        let server = IMKServer(name: connectionName, bundleIdentifier: bundleIdentifier)
        logger.notice("event=server_started")
        withExtendedLifetime(server) {
            NSApplication.shared.run()
        }
    }
}
