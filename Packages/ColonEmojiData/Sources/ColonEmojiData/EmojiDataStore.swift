import ColonModels
import Foundation

public struct EmojiDataLoadMetrics: Sendable, Equatable {
    public let durationNanoseconds: UInt64
    public let encodedDatasetByteCount: Int
    public let entryCount: Int

    public init(
        durationNanoseconds: UInt64,
        encodedDatasetByteCount: Int,
        entryCount: Int
    ) {
        self.durationNanoseconds = durationNanoseconds
        self.encodedDatasetByteCount = encodedDatasetByteCount
        self.entryCount = entryCount
    }
}

public struct EmojiDataSnapshot: Sendable {
    public let dataset: EmojiDataset
    public let entriesByID: [EmojiID: EmojiEntry]
    public let metrics: EmojiDataLoadMetrics

    public init(
        dataset: EmojiDataset,
        entriesByID: [EmojiID: EmojiEntry],
        metrics: EmojiDataLoadMetrics
    ) {
        self.dataset = dataset
        self.entriesByID = entriesByID
        self.metrics = metrics
    }
}

public final class EmojiDataStore: @unchecked Sendable {
    private enum State {
        case unloaded
        case loaded(EmojiDataSnapshot)
        case failed(EmojiDataError)
    }

    private let provider: any EmojiDataProviding
    private let lock = NSLock()
    private var state: State = .unloaded

    public init(provider: any EmojiDataProviding = BundledEmojiDataProvider.bundled()) {
        self.provider = provider
    }

    public func load() throws -> EmojiDataSnapshot {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case let .loaded(snapshot):
            return snapshot
        case let .failed(error):
            throw error
        case .unloaded:
            break
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds

        do {
            let dataset = try provider.loadDataset()
            let entriesByID = Dictionary(
                uniqueKeysWithValues: dataset.entries.map { ($0.id, $0) }
            )
            let encodedByteCount = (try? JSONEncoder().encode(dataset).count) ?? 0
            let metrics = EmojiDataLoadMetrics(
                durationNanoseconds: DispatchTime.now().uptimeNanoseconds - startedAt,
                encodedDatasetByteCount: encodedByteCount,
                entryCount: dataset.entries.count
            )
            let snapshot = EmojiDataSnapshot(
                dataset: dataset,
                entriesByID: entriesByID,
                metrics: metrics
            )
            state = .loaded(snapshot)
            return snapshot
        } catch let error as EmojiDataError {
            state = .failed(error)
            throw error
        } catch {
            state = .failed(.malformedResource)
            throw EmojiDataError.malformedResource
        }
    }
}
