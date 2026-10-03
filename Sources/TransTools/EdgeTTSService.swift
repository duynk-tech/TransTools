import Foundation
import CryptoKit
import AVFoundation

/// High-quality zero-cost Text-to-Speech using Microsoft Edge Neural Voices.
/// Connects via public Edge speech websocket protocol without requiring any API keys.
/// Automatically caches synthesized audio for instant offline replay.
public actor EdgeTTSService {
    public static let shared = EdgeTTSService()

    private var memoryCache: [String: Data] = [:]
    private let cacheDirectory: URL

    // Trusted Microsoft Edge Client Token
    private let clientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
    private let endpoint = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaheadwork/edge/v1"

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectory = caches.appendingPathComponent("TransToolsEdgeTTS", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    /// Best natural neural voice for each language
    public static func defaultVoice(for locale: String) -> String? {
        let loc = locale.lowercased()
        if loc.starts(with: "zh") {
            return "zh-CN-XiaoxiaoNeural" // Extremely warm & natural Mandarin
        } else if loc.starts(with: "ja") {
            return "ja-JP-NanamiNeural"   // Standard Tokyo natural female
        } else if loc.starts(with: "ko") {
            return "ko-KR-SunHiNeural"    // Standard Korean natural female
        } else if loc.starts(with: "vi") {
            return "vi-VN-HoaiMyNeural"   // Vietnamese natural female
        } else if loc == "en-in" {
            return "en-IN-NeerjaNeural"
        } else if loc.starts(with: "en") {
            return "en-US-JennyNeural"
        } else if loc.starts(with: "fr") {
            return "fr-FR-DeniseNeural"
        } else if loc.starts(with: "de") {
            return "de-DE-KatjaNeural"
        } else if loc.starts(with: "it") {
            return "it-IT-ElsaNeural"
        }
        return nil
    }

    /// Cache key for given text, locale and rate modifier
    private func cacheKey(text: String, voice: String, ratePercent: Int) -> String {
        let safeText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(safeText.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(voice)_\(ratePercent)_\(digest)"
    }

    /// Synthesize speech audio data (MP3 format) with automatic caching and fallback readiness
    public func synthesize(text: String, locale: String, rateModifier: Float = 1.0) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "EdgeTTS", code: -1, userInfo: [NSLocalizedDescriptionKey: "Nội dung đọc trống."])
        }

        guard let voice = Self.defaultVoice(for: locale) else {
            throw NSError(domain: "EdgeTTS", code: -4, userInfo: [NSLocalizedDescriptionKey: "Giọng Edge chưa hỗ trợ ngôn ngữ này."])
        }
        // Convert rateModifier (e.g. 0.75 -> -25%, 1.0 -> 0%)
        let ratePercent = Int(round((rateModifier - 1.0) * 100))
        let key = cacheKey(text: trimmed, voice: voice, ratePercent: ratePercent)

        // 1. Check memory cache
        if let cached = memoryCache[key] {
            return cached
        }

        // 2. Check disk cache
        let fileURL = cacheDirectory.appendingPathComponent("\(key).mp3")
        if let data = try? Data(contentsOf: fileURL), !data.isEmpty {
            memoryCache[key] = data
            return data
        }

        // 3. Connect via WebSocket
        let audioData = try await fetchFromWebSocket(text: trimmed, voice: voice, ratePercent: ratePercent)

        // Save to cache
        memoryCache[key] = audioData
        try? audioData.write(to: fileURL)

        return audioData
    }

    private func fetchFromWebSocket(text: String, voice: String, ratePercent: Int) async throws -> Data {
        let connectionId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        guard let url = URL(string: "\(endpoint)?TrustedClientToken=\(clientToken)&ConnectionId=\(connectionId)") else {
            throw NSError(domain: "EdgeTTS", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid Edge TTS URL"])
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0", forHTTPHeaderField: "User-Agent")
        request.setValue("chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold", forHTTPHeaderField: "Origin")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let session = URLSession(configuration: .ephemeral)
        let webSocket = session.webSocketTask(with: request)
        webSocket.resume()
        defer { webSocket.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }

        let rateString = ratePercent >= 0 ? "+\(ratePercent)%" : "\(ratePercent)%"
        let ssml = """
        <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='\(voice.split(separator: "-").prefix(2).joined(separator: "-"))'>
            <voice name='\(voice)'>
                <prosody pitch='+0Hz' rate='\(rateString)' volume='+0%'>
                    \(escapeXml(text))
                </prosody>
            </voice>
        </speak>
        """

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let configMessage = "X-Timestamp:\(timestamp)\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}"

        let requestId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let ssmlMessage = "X-RequestId:\(requestId)\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:\(timestamp)Z\r\nPath:ssml\r\n\r\n\(ssml)"

        // Send handshake and SSML
        try await webSocket.send(.string(configMessage))
        try await webSocket.send(.string(ssmlMessage))

        // Collect audio stream
        var accumulatedAudio = Data()
        var isTurnFinished = false
        let maxTimeoutSeconds: TimeInterval = 6.0
        let startTime = Date()

        while !isTurnFinished {
            if Date().timeIntervalSince(startTime) > maxTimeoutSeconds {
                webSocket.cancel(with: .goingAway, reason: nil)
                throw NSError(domain: "EdgeTTS", code: -3, userInfo: [NSLocalizedDescriptionKey: "Hết thời gian kết nối giọng đọc."])
            }

            let remaining = max(0.1, maxTimeoutSeconds - Date().timeIntervalSince(startTime))
            let message = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
                group.addTask { try await webSocket.receive() }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    webSocket.cancel(with: .goingAway, reason: nil)
                    throw NSError(domain: "EdgeTTS", code: -3, userInfo: [NSLocalizedDescriptionKey: "Hết thời gian kết nối giọng đọc."])
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw CancellationError() }
                return result
            }
            switch message {
            case .data(let rawData):
                // Look for binary header delimiter "\r\n\r\n" or 2-byte header length in Edge protocol
                if rawData.count > 2 {
                    let headerLength = Int(rawData[0]) << 8 | Int(rawData[1])
                    if rawData.count > (headerLength + 2) {
                        let headerData = rawData.subdata(in: 2..<(headerLength + 2))
                        if let headerString = String(data: headerData, encoding: .utf8), headerString.contains("Path:audio") {
                            let payload = rawData.subdata(in: (headerLength + 2)..<rawData.count)
                            accumulatedAudio.append(payload)
                        }
                    }
                }
            case .string(let textMessage):
                if textMessage.contains("Path:turn.end") {
                    isTurnFinished = true
                }
            @unknown default:
                break
            }
        }

        webSocket.cancel(with: .normalClosure, reason: nil)

        guard !accumulatedAudio.isEmpty else {
            throw NSError(domain: "EdgeTTS", code: -4, userInfo: [NSLocalizedDescriptionKey: "Không nhận được dữ liệu âm thanh."])
        }

        return accumulatedAudio
    }

    private func escapeXml(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
