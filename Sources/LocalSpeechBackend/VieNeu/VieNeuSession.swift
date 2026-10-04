import Foundation

private final class VieNeuCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    private var epoch = UUID()
    func snapshot() -> UUID { lock.lock(); defer { lock.unlock() }; return epoch }
    func invalidate() { lock.lock(); epoch = UUID(); lock.unlock() }
    func check(_ expected: UUID) throws { lock.lock(); let same = epoch == expected; lock.unlock(); if !same { throw CancellationError() } }
    func cancel() { lock.lock(); value = true; lock.unlock() }
    func check() throws { lock.lock(); let cancelled = value; lock.unlock(); if cancelled { throw CancellationError() }; try Task.checkCancellation() }
}

/// ONNX sessions and the mmap pronunciation dictionary live off the main actor.
/// One request at a time; explicit cancellation is checked between graph calls.
public actor VieNeuSession {
    public static let shared = VieNeuSession()
    private var model: VieNeuModel?
    private var directory: URL?
    private var active: UUID?
    private var idle: Task<Void, Never>?
    private nonisolated let cancellation = VieNeuCancellation()
    private var requestCancellation: VieNeuCancellation?
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    public nonisolated func stop() { cancellation.invalidate(); Task { await self.releaseIfIdle() } }
    private func cancelAndRelease() { requestCancellation?.cancel(); model = nil; directory = nil; idle?.cancel() }
    public func release() async {
        cancellation.invalidate(); requestCancellation?.cancel(); idle?.cancel()
        if active != nil { await withCheckedContinuation { releaseWaiters.append($0) } }
        model = nil; directory = nil
    }
    public func synthesize(text: String, voice: String, directory: URL, resources: URL,
                           emit: @escaping @Sendable ([Float]) async throws -> Void) async throws {
        guard active == nil else { throw vieNeuError("VieNeu đang xử lý một đoạn đọc khác.") }
        let epoch = cancellation.snapshot()
        let id = UUID(), request = VieNeuCancellation(); active = id; requestCancellation = request
        idle?.cancel()
        defer {
            if active == id { active = nil; requestCancellation = nil }
            if (try? request.check()) == nil || (try? cancellation.check(epoch)) == nil { model = nil; self.directory = nil }
            if !releaseWaiters.isEmpty {
                model = nil; self.directory = nil
                let waiters = releaseWaiters; releaseWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
            idle = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
                await self?.releaseIfIdle()
            }
        }
        try await withTaskCancellationHandler(operation: {
            try request.check()
            if model == nil || self.directory != directory {
                model = try VieNeuModel(directory: directory, resources: resources); self.directory = directory
            }
            guard let loaded = model else { throw CancellationError() }
            for attempt in 0...2 {
                do {
                    try await loaded.synthesize(text: text, voice: voice, check: { try request.check(); try self.cancellation.check(epoch) }, emit: emit)
                    break
                } catch {
                    // Only retry a capped short phrase: those samples are held
                    // until EOS, so a retry never repeats already-played audio.
                    guard (error as NSError).domain == "VieNeuNative", (error as NSError).code == 2, attempt < 2 else { throw error }
                }
            }
        }, onCancel: { request.cancel() })
    }
    private func releaseIfIdle() { if active == nil { model = nil; directory = nil } }
}
