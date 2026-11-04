import ColonModels
import Foundation

public struct ColonDiagnosticReport: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let appVersion: String
    public let operatingSystemVersion: String
    public let inputMethodReadiness: InputMethodReadinessSnapshot
    public let events: [DiagnosticEvent]

    public init(
        generatedAt: Date,
        appVersion: String,
        operatingSystemVersion: String,
        inputMethodReadiness: InputMethodReadinessSnapshot,
        events: [DiagnosticEvent]
    ) {
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.operatingSystemVersion = operatingSystemVersion
        self.inputMethodReadiness = inputMethodReadiness
        self.events = events
    }
}

public final class DiagnosticEventBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var events: [DiagnosticEvent] = []

    public init(capacity: Int = 200) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public func append(_ event: DiagnosticEvent) {
        lock.withLock {
            events.append(event)
            if events.count > capacity {
                events.removeFirst(events.count - capacity)
            }
        }
    }

    public func snapshot() -> [DiagnosticEvent] {
        lock.withLock { events }
    }
}

public struct DiagnosticReportEncoder: Sendable {
    public init() {}

    public func encode(_ report: ColonDiagnosticReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }
}
