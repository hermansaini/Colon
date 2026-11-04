import Foundation

public enum SettingsChangeNotification {
    public static let name = Notification.Name("org.colonproject.settings.changed")
    public static let originKey = "origin"
    public static let processOrigin = UUID().uuidString
}

public protocol SettingsChangePosting: Sendable {
    func postSettingsChanged()
}

public struct DistributedSettingsChangePoster: SettingsChangePosting {
    public init() {}

    public func postSettingsChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            SettingsChangeNotification.name,
            object: nil,
            userInfo: [SettingsChangeNotification.originKey: SettingsChangeNotification.processOrigin],
            deliverImmediately: true
        )
    }
}
