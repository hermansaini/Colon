import ColonEmojiData
import ColonSearch
import Foundation

// Synthetic inputs only. This executable never reads application text or settings.
func elapsedMilliseconds(_ operation: () throws -> Void) rethrows -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    try operation()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}
func percentile(_ samples: [Double], _ fraction: Double) -> Double {
    let sorted = samples.sorted()
    return sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * fraction)) - 1)]
}
let store = EmojiDataStore()
let snapshot = try store.load()
var engine: EmojiSearchEngine!
let indexMilliseconds = elapsedMilliseconds {
    engine = EmojiSearchEngine(dataset: snapshot.dataset)
}
let queries = ["f", "fi", "fire", "hand", "wave", "thumbsup", "thumbs_up", "heart", "flag", "face", "ing", "zzzzzz", "raised_fist", "woman", "a"]
var samples: [Double] = []
var resultCount = 0
for query in queries { _ = engine.search(query: query, maximumResultCount: 50) }
for _ in 0..<100 {
    for query in queries {
        samples.append(elapsedMilliseconds {
            resultCount += engine.search(query: query, maximumResultCount: 50).count
        })
    }
}
let report: [String: Any] = [
    "environment": ProcessInfo.processInfo.operatingSystemVersionString,
    "entryCount": snapshot.metrics.entryCount,
    "encodedDatasetBytes": snapshot.metrics.encodedDatasetByteCount,
    "coldLoadMilliseconds": Double(snapshot.metrics.durationNanoseconds) / 1_000_000,
    "indexBuildMilliseconds": indexMilliseconds,
    "queryCount": samples.count,
    "queryP50Milliseconds": percentile(samples, 0.50),
    "queryP95Milliseconds": percentile(samples, 0.95),
    "queryMaxMilliseconds": samples.max()!,
    "resultCountChecksum": resultCount,
    "queryP95TargetMet": percentile(samples, 0.95) < 5,
]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
if percentile(samples, 0.95) >= 5 { exit(1) }
