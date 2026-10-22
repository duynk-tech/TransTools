import Foundation

/// Developer-only local trace. No output unless an explicit path is supplied.
/// Limits both pending work and disk usage; never blocks the audio/UI thread on IO.
final class MeetingRecognitionTrace: @unchecked Sendable {
    struct Event: Codable {
        struct Word: Codable { let text: String; let start: Double; let end: Double }
        let phase: String
        let generation: UUID
        let currentID: UUID
        let raw: String
        let committed: String
        let rotationTail: String
        let captionCount: Int
        let liveText: String
        let final: Bool
        var elapsed: Double = 0
        var words: [Word] = []
    }
    private let url: URL
    var destination: URL { url }
    private let maximumBytes: Int
    private let queue = DispatchQueue(label: "TransTools.recognition-trace", qos: .utility)
    private let lock = NSLock()
    private var pending = 0
    private var sequence = 0
    private var exhausted = false // Access only on queue.

    static func fromEnvironment() -> MeetingRecognitionTrace? {
        guard let path = ProcessInfo.processInfo.environment["TRANS_TOOLS_RECOGNITION_TRACE"],
              path.hasPrefix("/"), !path.isEmpty else { return nil }
        return MeetingRecognitionTrace(url: URL(fileURLWithPath: path))
    }
    init(url: URL, maximumBytes: Int = 10 * 1024 * 1024) {
        self.url = url
        self.maximumBytes = max(0, maximumBytes)
    }
    func record(_ event: Event) {
        lock.lock()
        sequence += 1
        let eventSequence = sequence
        guard pending < 32 else { lock.unlock(); return }
        pending += 1
        lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); pending -= 1; lock.unlock() }
            guard !exhausted else { return }
            do {
                struct Entry: Encodable { let sequence: Int; let event: Event }
                var data = try JSONEncoder().encode(Entry(sequence: eventSequence, event: event))
                data.append(0x0A)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try Data().write(to: url, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                let size = try handle.seekToEnd()
                guard size <= UInt64(maximumBytes), data.count <= maximumBytes - Int(size) else {
                    exhausted = true
                    return
                }
                try handle.write(contentsOf: data)
            } catch { exhausted = true }
        }
    }
    /// For test teardown only; production does not wait for disk writes.
    func flushForTesting() { queue.sync {} }
}
