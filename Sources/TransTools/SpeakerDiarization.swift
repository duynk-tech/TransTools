import Foundation
import AVFoundation
import CoreMedia
import FluidAudio

struct SpeakerInterval: Codable, Equatable {
    let start: Double
    let end: Double
    let speaker: Int?
}

/// All inference runs off the audio capture and UI threads. Identity lasts one meeting only.
final class SpeakerDiarization {
    private let queue = DispatchQueue(label: "TransTools.speakers", qos: .utility)
    private let stateLock = NSLock()
    private var accepting = false
    private var acceptsAudio: Bool { stateLock.lock(); defer { stateLock.unlock() }; return accepting }
    private let slots = DispatchSemaphore(value: 250)
    private let converter = AudioConverter()
    private var manager: DiarizerManager?
    private var samples: [Float] = []
    private var started = Date()
    private var offset: Double = 0
    private var identities: [String: Int] = [:]
    private var token = UUID()
    private var enabled = false
    var onIntervals: ((UUID, [SpeakerInterval], Double) -> Void)?
    private var committedThrough: Double = 0
    var onStatus: ((UUID, String) -> Void)?

    func start(token: UUID, at date: Date) {
        stateLock.lock(); accepting = true; stateLock.unlock()
        queue.async {
            self.token = token; self.started = date; self.samples = []; self.identities = [:]; self.offset = 0; self.committedThrough = 0
            self.manager = nil; self.enabled = true
            self.onStatus?(token, "Đang tải/nạp mô hình tách giọng…")
            Task {
                do {
                    let models = try await DiarizerModels.downloadIfNeeded()
                    self.queue.async {
                        guard self.token == token, self.enabled else { return }
                        let manager = DiarizerManager()
                        manager.initialize(models: models)
                        self.manager = manager
                        self.drainReadyChunks()
                        self.onStatus?(token, "Tách giọng trên máy · nhãn cập nhật sau khoảng 10 giây")
                    }
                } catch {
                    self.queue.async {
                        guard self.token == token else { return }
                        self.enabled = false
                        self.onStatus?(token, "Không nạp được mô hình tách giọng: " + error.localizedDescription)
                    }
                }
            }
        }
    }
    func stop() {
        stateLock.lock(); accepting = false; stateLock.unlock()
        queue.async {
            if self.samples.count >= 16000 { self.process(self.samples, offset: self.offset, through: self.offset + Double(self.samples.count) / 16000) }
            self.enabled = false; self.samples = []; self.manager = nil
        }
    }
    func append(_ sample: CMSampleBuffer) {
        guard acceptsAudio else { return }
        submit { try self.converter.resampleSampleBuffer(sample) }
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        guard acceptsAudio else { return }
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (src, dst) in zip(source, destination) {
            if let a = src.mData, let b = dst.mData { memcpy(b, a, Int(src.mDataByteSize)) }
        }
        submit { try self.converter.resampleBuffer(copy) }
    }
    private func submit(_ conversion: @escaping () throws -> [Float]) {
        guard slots.wait(timeout: .now()) == .success else { return }
        let received = Date()
        queue.async {
            defer { self.slots.signal() }
            guard self.enabled else { return }
            do {
                let audio = try conversion()
                let audioStart = max(0, received.timeIntervalSince(self.started) - Double(audio.count) / 16000)
                if self.samples.isEmpty { self.offset = audioStart }
                let expectedStart = self.offset + Double(self.samples.count) / 16000
                if audioStart - expectedStart > 0.3 {
                    // A capture gap must not compress the timeline and shift speaker labels.
                    if self.manager == nil, audioStart - expectedStart <= 30 {
                        self.samples.append(contentsOf: repeatElement(0, count: Int((audioStart - expectedStart) * 16000)))
                    } else {
                        if self.samples.count >= 16000 {
                            self.process(self.samples, offset: self.offset, through: expectedStart)
                        }
                        self.samples = []; self.offset = audioStart
                    }
                }
                self.samples.append(contentsOf: audio)
                if self.manager == nil, self.samples.count > 480000 {
                    let removed = self.samples.count - 480000
                    self.samples.removeFirst(removed)
                    self.offset += Double(removed) / 16000
                    self.onStatus?(self.token, "Mô hình chưa sẵn sàng · đang giữ 30 giây audio gần nhất")
                }
                self.drainReadyChunks()
            } catch { self.onStatus?(self.token, "Không phân tích được audio tách giọng: " + error.localizedDescription) }
        }
    }
    private func drainReadyChunks() {
        guard manager != nil else { return }
        // Retain two seconds of context at each boundary; only commit the first eight.
        while samples.count >= 160000 {
            process(Array(samples.prefix(160000)), offset: offset, through: offset + 8)
            samples.removeFirst(128000)
            offset += 8
        }
    }
    private func process(_ audio: [Float], offset: Double, through: Double) {
        guard let manager else { return }
        do {
            let result = try manager.performCompleteDiarization(audio)
            let intervals = result.segments.compactMap { segment -> SpeakerInterval? in
                let start = max(self.committedThrough, offset + Double(segment.startTimeSeconds))
                let end = min(through, offset + Double(segment.endTimeSeconds))
                guard end > start else { return nil }
                var id: Int?
                if !segment.speakerId.isEmpty, segment.qualityScore > 0.01 {
                    if self.identities[segment.speakerId] == nil { self.identities[segment.speakerId] = self.identities.count + 1 }
                    id = self.identities[segment.speakerId]
                }
                return SpeakerInterval(start: start, end: end, speaker: id)
            }
            committedThrough = max(committedThrough, through)
            onIntervals?(token, intervals, committedThrough)
        } catch { onStatus?(token, "Tách giọng chưa có kết quả: " + error.localizedDescription) }
    }
}

/// Require a dominant voice over the word, rather than guessing at its midpoint.
enum SpeakerWordAssignment {
    static func speaker(start: Double, end: Double, intervals: [SpeakerInterval]) -> Int? {
        guard start.isFinite, end.isFinite, end > start else { return nil }
        var ranges: [Int: [(Double, Double)]] = [:]
        for interval in intervals {
            guard let speaker = interval.speaker else { continue }
            let a = max(start, interval.start), b = min(end, interval.end)
            if b > a { ranges[speaker, default: []].append((a, b)) }
        }
        let scores = ranges.map { speaker, spans -> (Int, Double) in
            var coverage = 0.0, coveredThrough = start
            for span in spans.sorted(by: { $0.0 < $1.0 }) {
                coverage += max(0, span.1 - max(coveredThrough, span.0))
                coveredThrough = max(coveredThrough, span.1)
            }
            return (speaker, coverage)
        }.sorted { $0.1 > $1.1 }
        let duration = end - start
        guard let best = scores.first, best.1 >= duration * 0.6,
              best.1 - (scores.dropFirst().first?.1 ?? 0) >= duration * 0.2 else { return nil }
        return best.0
    }
}
