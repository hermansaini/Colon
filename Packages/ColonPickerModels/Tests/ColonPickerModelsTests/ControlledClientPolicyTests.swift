import ColonModels
import XCTest
@testable import ColonPickerModels

final class InputClientPolicyTests: XCTestCase {
    private let policy = InputClientPolicy()

    func testAllowsAllEightSupportedApplicationsByDefault() {
        let settings = ColonSettingsSnapshot.defaults
        for application in SupportedApplication.allCases {
            XCTAssertEqual(
                policy.decision(
                    context: context(application.rawValue),
                    settings: settings
                ),
                .allowed,
                application.displayName
            )
        }
    }

    func testRejectsGlobalAndPerApplicationDisablement() {
        var settings = ColonSettingsSnapshot.defaults
        settings.isEnabled = false
        XCTAssertEqual(
            policy.decision(
                context: context(SupportedApplication.notes.rawValue),
                settings: settings
            ),
            .globallyDisabled
        )

        for application in SupportedApplication.allCases {
            settings = .defaults
            settings.enabledApps[application.rawValue] = false
            XCTAssertEqual(
                policy.decision(context: context(application.rawValue), settings: settings),
                .applicationDisabled,
                application.displayName
            )
        }
    }

    func testRejectsSecureAndUnknownSecurityState() {
        let settings = ColonSettingsSnapshot.defaults
        XCTAssertEqual(
            policy.decision(
                context: context(
                    SupportedApplication.safari.rawValue,
                    secureEventInputEnabled: true
                ),
                settings: settings
            ),
            .secureInput
        )
        XCTAssertEqual(
            policy.decision(
                context: context(
                    SupportedApplication.safari.rawValue,
                    secureEventInputEnabled: nil
                ),
                settings: settings
            ),
            .securityStateUnavailable
        )
    }

    func testRejectsMissingUnknownAndTextEditClients() {
        let settings = ColonSettingsSnapshot.defaults
        XCTAssertEqual(
            policy.decision(
                context: InputClientSecurityContext(
                    clientBundleIdentifier: nil,
                    frontmostBundleIdentifier: nil,
                    secureEventInputEnabled: false
                ),
                settings: settings
            ),
            .clientIdentityUnavailable
        )
        XCTAssertEqual(
            policy.decision(context: context("com.example.Unknown"), settings: settings),
            .unsupportedApplication
        )
        XCTAssertEqual(
            policy.decision(context: context("com.apple.TextEdit"), settings: settings),
            .unsupportedApplication
        )
    }

    func testRejectsAppSwitchClientMismatch() {
        let settings = ColonSettingsSnapshot.defaults
        XCTAssertEqual(
            policy.decision(
                context: InputClientSecurityContext(
                    clientBundleIdentifier: SupportedApplication.notes.rawValue,
                    frontmostBundleIdentifier: SupportedApplication.messages.rawValue,
                    secureEventInputEnabled: false
                ),
                settings: settings
            ),
            .clientApplicationMismatch
        )
    }

    private func context(
        _ bundleIdentifier: String,
        secureEventInputEnabled: Bool? = false
    ) -> InputClientSecurityContext {
        InputClientSecurityContext(
            clientBundleIdentifier: bundleIdentifier,
            frontmostBundleIdentifier: bundleIdentifier,
            secureEventInputEnabled: secureEventInputEnabled
        )
    }
}
