import Foundation
import AVFoundation
import LocalSpeechBackend

/// A single serial worker keeps only one SDK/model resident. Text travels through private pipes.
final class ExternalTTSSession: @unchecked Sendable {
    static let shared = ExternalTTSSession()
    private let queue = DispatchQueue(label: "TransTools.LocalTTS.worker", qos: .userInitiated)
    private let lock = NSLock()
    private var process: Process?
    private var activeModel: ExternalTTSModel?
    private var input: FileHandle?
    private var output: FileHandle?
    private var pending = Data()
    private var idle: DispatchWorkItem?
    private var generation = UUID()
    private var activeRequest: UUID?
    private let workerResources: URL?
    private var memoryPressure: DispatchSourceMemoryPressure?
    init(resources: URL? = ExternalTTSModelManager.resources) {
        workerResources = resources
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in self?.stop() }
        source.resume(); memoryPressure = source
    }
    deinit { memoryPressure?.cancel() }
    func stop() {
        VieNeuSession.shared.stop()
        stopPython()
    }
    private func stopPython() {
        lock.lock(); generation = UUID(); idle?.cancel(); idle = nil
        let p = process; lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }
    func cancelCurrent() {
        VieNeuSession.shared.stop()
        lock.lock(); generation = UUID(); let p = activeRequest == nil ? nil : process; lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }
    func releaseAndWait() async {
        VieNeuSession.shared.stop()
        await VieNeuSession.shared.release()
        await releasePythonAndWait()
    }
    private func releasePythonAndWait() async {
        stopPython()
        await withCheckedContinuation { continuation in
            queue.async {
                self.lock.lock(); let p = self.process; self.lock.unlock()
                if let p, p.isRunning { p.waitUntilExit() }
                self.activeModel = nil; self.input = nil; self.output = nil
                self.pending.removeAll(keepingCapacity: false)
                self.lock.lock(); self.process = nil; self.lock.unlock()
                continuation.resume()
            }
        }
    }
    func synthesize(model: ExternalTTSModel, text: String, language: String, options: TTSOptions, voice: String? = nil, onChunk: (@Sendable (TTSAudioResult) async throws -> Void)? = nil) async throws -> TTSAudioResult {
        if model == .vieneu {
            guard model.isInstalled, LanguageVoicePreferences.code(language) == "vi" else {
                throw failure("VieNeu chưa cài hoặc ngôn ngữ chưa hỗ trợ.")
            }
            await releasePythonAndWait()
            return try await NativeVieNeu.shared.synthesize(text: text, voice: voice ?? model.selectedVoice(for: language), options: options, onChunk: onChunk)
        }
        await VieNeuSession.shared.release()
        let requestID = UUID()
        let cancellation = TTSRequestCancellation()
        let epoch = lock.withLock { generation }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    var ownsWorker = false
                    do {
                        self.lock.lock()
                        let allowed = self.generation == epoch && !cancellation.isCancelled
                        if allowed { self.activeRequest = requestID }
                        self.lock.unlock()
                        guard allowed else { throw CancellationError() }
                        ownsWorker = true
                        defer { self.lock.lock(); if self.activeRequest == requestID { self.activeRequest = nil }; self.lock.unlock() }
                        try self.ensureWorker(model)
                        guard !cancellation.isCancelled, self.lock.withLock({ self.generation == epoch }) else { throw CancellationError() }
                        let wav = try self.request(model: model, id: requestID, text: text, language: language, options: options, voice: voice, onChunk: onChunk)
                        continuation.resume(returning: wav)
                    } catch {
                        self.lock.lock(); let p = self.process; self.lock.unlock()
                        if ownsWorker, let p, p.isRunning { p.terminate() }
                        continuation.resume(throwing: error)
                    }
                }
            }
        }, onCancel: {
            cancellation.cancel()
            self.lock.lock(); let owns = self.activeRequest == requestID; let p = self.process; self.lock.unlock()
            if owns, let p, p.isRunning { p.terminate() }
        })
    }
    private func ensureWorker(_ model: ExternalTTSModel) throws {
        lock.lock(); let old = process; lock.unlock()
        if activeModel == model, old?.isRunning == true { return }
        if let old, old.isRunning { old.terminate(); old.waitUntilExit() }
        input = nil; output = nil; pending.removeAll(keepingCapacity: false)
        guard model.isInstalled, let resources = workerResources else {
            throw failure("Mô hình chưa cài hoặc chưa kiểm thử thành công.")
        }
        let p = Process(); p.executableURL = model.python
        p.arguments = [resources.appendingPathComponent("worker.py").path, "--engine", model.rawValue, "--root", model.directory.path]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr
        // Discard third-party diagnostics: never log the user's reading or conversation.
        stderr.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        p.terminationHandler = { _ in stderr.fileHandleForReading.readabilityHandler = nil }
        lock.lock(); process = p; idle?.cancel()
        do { try p.run() } catch { process = nil; lock.unlock(); throw error }
        lock.unlock()
        activeModel = model; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        let timeout = timeoutFor(p, seconds: 120); defer { timeout.cancel() }
        let ready = try readObject()
        guard ready["ready"] as? Bool == true else { throw failure("Không nạp được mô hình Local.") }
    }
    private func request(model: ExternalTTSModel, id: UUID, text: String, language: String, options: TTSOptions, voice: String?, onChunk: (@Sendable (TTSAudioResult) async throws -> Void)?) throws -> TTSAudioResult {
        lock.lock(); idle?.cancel(); let p = process; let token = generation; lock.unlock()
        guard let p, p.isRunning, let input else { throw CancellationError() }
        let timeout = timeoutFor(p, seconds: 60); defer { timeout.cancel() }
        let object: [String: Any] = ["id": id.uuidString, "text": text, "language": LanguageVoicePreferences.code(language),
            "stream": onChunk != nil, "voice": voice ?? model.selectedVoice(for: language), "volume": options.volume, "speed": onChunk == nil ? max(0.7, min(1.5, options.rate / 0.44)) : 1]
        var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
        try input.write(contentsOf: data)
        var last: TTSAudioResult?
        while true {
            let response = try readObject()
            lock.lock(); let current = generation == token; lock.unlock()
            guard current, response["id"] as? String == id.uuidString else { throw CancellationError() }
            if let error = response["error"] as? String { throw failure("Mô hình không tạo được audio: " + error) }
            if response["done"] as? Bool == true { break }
            guard let encoded = response["wav"] as? String, let wav = Data(base64Encoded: encoded),
                  let sampleRate = response["sampleRate"] as? Double, let duration = response["duration"] as? Double,
                  duration > 0, duration <= 120, wav.count > 44 else { throw failure("Audio trả về không hợp lệ.") }
            let result = TTSAudioResult(audioData: wav, duration: duration, sampleRate: sampleRate, engineType: model.title,
                metadata: ["model": model.rawValue, "latencyMs": String(describing: response["latencyMs"] ?? 0)])
            if let onChunk {
                let signal = DispatchSemaphore(value: 0)
                let outcome = TTSChunkOutcome()
                Task {
                    do { try await onChunk(result) } catch { outcome.error = error }
                    signal.signal()
                }
                // Producer backpressure: no unbounded stream of WAV packets in RAM.
                signal.wait()
                if let error = outcome.error { throw error }
            }
            last = result
            if response["chunk"] as? Bool != true { break }
        }
        guard let last else { throw failure("Mô hình không trả audio.") }
        let work = DispatchWorkItem { [weak self, weak p] in
            guard let self, let p else { return }
            self.lock.lock(); let same = self.process === p; self.lock.unlock()
            if same, p.isRunning { p.terminate() }
        }
        lock.lock(); idle = work; lock.unlock()
        queue.asyncAfter(deadline: .now() + 120, execute: work)
        return last
    }
    private func readObject() throws -> [String: Any] {
        guard let output else { throw CancellationError() }
        while true {
            if let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline)
                let data = Data(line); pending.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure("Phản hồi mô hình không hợp lệ.") }
                return object
            }
            let block = output.availableData
            guard !block.isEmpty else { throw failure("Bộ xử lý Local đã dừng hoặc không đủ bộ nhớ.") }
            pending.append(block)
            guard pending.count <= 20 * 1024 * 1024 else { throw failure("Audio vượt giới hạn bộ nhớ.") }
        }
    }
    private func timeoutFor(_ p: Process, seconds: Double) -> DispatchWorkItem {
        let work = DispatchWorkItem { [weak p] in if let p, p.isRunning { p.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: work)
        return work
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "ExternalTTS", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

private final class TTSRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

private final class TTSChunkOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?
    var error: Error? {
        get { lock.withLock { storedError } }
        set { lock.withLock { storedError = newValue } }
    }
}
