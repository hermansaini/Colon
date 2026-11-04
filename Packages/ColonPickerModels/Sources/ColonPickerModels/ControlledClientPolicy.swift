import ColonModels

public struct InputClientSecurityContext: Equatable, Sendable {
    public let clientBundleIdentifier: String?
    public let frontmostBundleIdentifier: String?
    public let secureEventInputEnabled: Bool?

    public init(
        clientBundleIdentifier: String?,
        frontmostBundleIdentifier: String?,
        secureEventInputEnabled: Bool?
    ) {
        self.clientBundleIdentifier = clientBundleIdentifier
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.secureEventInputEnabled = secureEventInputEnabled
    }
}

public enum InputClientDecision: Equatable, Sendable {
    case allowed
    case globallyDisabled
    case secureInput
    case securityStateUnavailable
    case clientIdentityUnavailable
    case clientApplicationMismatch
    case unsupportedApplication
    case applicationDisabled
}

public struct InputClientPolicy: Sendable {
    public init() {}

    public func decision(
        context: InputClientSecurityContext,
        settings: ColonSettingsSnapshot
    ) -> InputClientDecision {
        guard settings.isEnabled else {
            return .globallyDisabled
        }
        guard let secureEventInputEnabled = context.secureEventInputEnabled else {
            return .securityStateUnavailable
        }
        guard secureEventInputEnabled == false else {
            return .secureInput
        }
        guard let bundleIdentifier = context.clientBundleIdentifier,
              bundleIdentifier.isEmpty == false,
              let frontmostBundleIdentifier = context.frontmostBundleIdentifier,
              frontmostBundleIdentifier.isEmpty == false
        else {
            return .clientIdentityUnavailable
        }
        guard bundleIdentifier == frontmostBundleIdentifier else {
            return .clientApplicationMismatch
        }
        guard let application = SupportedApplication(rawValue: bundleIdentifier) else {
            return .unsupportedApplication
        }
        return settings.enabledApps[application.rawValue] == true
            ? .allowed
            : .applicationDisabled
    }
}
