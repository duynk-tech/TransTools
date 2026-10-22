import Foundation

// Conservative energy gate, not a speaker/neural classifier. A very low floor
// protects quiet speech; unsupported formats fail open. Keep 1.5s hangover so
// punctuation/final results can settle before long digital silence is skipped.
struct SpeechSilenceGate {
    var silentDuration: Double = 0
    var skippedDuration: Double = 0
    let hangover = 1.5
    let preRoll = 0.25
    mutating func shouldForward(rms: Double?, duration: Double) -> Bool {
        guard let rms, rms.isFinite, duration.isFinite, duration > 0 else {
            silentDuration = 0
            return true
        }
        // -66 dBFS floor: avoid classifying soft speech as background noise.
        if rms > 0.0005 { silentDuration = 0; return true }
        silentDuration += duration
        if silentDuration <= hangover + 0.000001 { return true }
        skippedDuration += duration
        return false
    }
}

// Recognition offsets refer to the compacted stream. Translate them back to
// capture time, including silence gaps and the replay ring at session rotation.
struct SpeechAudioTimeline {
    struct Span { var offset: Double; var duration: Double; var wall: Double }
    private(set) var spans: [Span] = []
    private(set) var duration: Double = 0
    mutating func append(duration seconds: Double, endingAt date: Date) {
        guard seconds.isFinite, seconds > 0 else { return }
        let wall = date.timeIntervalSince1970 - seconds
        if let last = spans.last, abs(last.wall + last.duration - wall) < 0.03 {
            spans[spans.count - 1].duration += seconds
        } else {
            spans.append(Span(offset: duration, duration: seconds, wall: wall))
        }
        duration += seconds
    }
    func wallTime(at offset: Double, fallback: Double, isEnd: Bool = false) -> Double {
        guard let span = spans.last(where: { isEnd ? $0.offset < offset : $0.offset <= offset }) ?? spans.first else { return fallback + offset }
        return span.wall + max(0, min(span.duration, offset - span.offset))
    }
}

// Recovery uses actual voiced audio, not meter/UI updates or repeated callbacks.
struct SpeechProgressWatchdog {
    private var lastProgress = Date()
    private var lastText = ""
    private var voicedSeconds: Double = 0
    private var lastVoice = Date.distantPast
    mutating func reset(at now: Date = Date()) {
        lastProgress = now; lastText = ""; voicedSeconds = 0; lastVoice = .distantPast
    }
    mutating func audio(rms: Double?, duration: Double, at now: Date) {
        guard duration.isFinite, duration > 0 else { return }
        // Unsupported meter formats fail open, just like the silence gate.
        // Otherwise audio can be forwarded forever without ever recovering.
        if let rms, rms.isFinite, rms <= 0.0005 { return }
        voicedSeconds += duration; lastVoice = now
    }
    mutating func result(_ text: String, at now: Date) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != lastText else { return }
        lastText = normalized; lastProgress = now; voicedSeconds = 0
    }
    func stalled(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastProgress) >= 10 && voicedSeconds >= 4 && now.timeIntervalSince(lastVoice) <= 3
    }
}
