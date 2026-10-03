import Foundation
import AppKit
import Vision
import NaturalLanguage
import SwiftUI

@MainActor
final class ScreenOCRService: ObservableObject {
    static let shared = ScreenOCRService()

    @Published var showReview = false
    @Published var sourceLanguage: AppLanguage = .english
    @Published var targetLanguage: AppLanguage = .vietnamese
    @Published var notice = ""
    @Published var isCapturing: Bool = false
    @Published var lastOCRText: String = ""
    @Published var lastTranslatedText: String = ""
    @Published var isTranslating: Bool = false

    private init() {}

    func triggerScreenOCRTranslation() {
        startInteractiveScreenCaptureAndTranslate()
    }

    /// Kích hoạt chụp ảnh màn hình bằng screencapture interactive của macOS (-i), sau đó nhận diện văn bản OCR và dịch
    func startInteractiveScreenCaptureAndTranslate() {
        guard !isCapturing else { return }
        isCapturing = true

        let tempImageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TransTools_OCR_\(UUID().uuidString).png")

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            // -i: interactive select area, -s: mouse selection only, -x: no sound
            process.arguments = ["-i", "-s", "-x", tempImageURL.path]

            do {
                try process.run()
                process.waitUntilExit()
                let captureFailed = process.terminationStatus != 0

                if FileManager.default.fileExists(atPath: tempImageURL.path) {
                    let image = NSImage(contentsOf: tempImageURL)
                    try? FileManager.default.removeItem(at: tempImageURL)

                    if let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        let recognizedText = await self.performVisionOCR(cgImage: cgImage)
                        await MainActor.run {
                            self.handleRecognizedText(recognizedText)
                        }
                    } else {
                        await MainActor.run {
                            self.isCapturing = false
                        }
                    }
                } else {
                    // Huỷ chụp bình thường không mở cửa sổ.
                    await MainActor.run {
                        if captureFailed {
                            self.lastOCRText = ""; self.lastTranslatedText = ""
                            self.notice = "Chưa chụp được màn hình. Kiểm tra quyền Ghi màn hình cho TransTools trong Cài đặt hệ thống rồi thử lại."
                            self.showReview = true
                        }
                        self.isCapturing = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastOCRText = ""; self.lastTranslatedText = ""
                    self.notice = "Không mở được công cụ chụp màn hình. Hãy thử lại."
                    self.showReview = true
                    self.isCapturing = false
                }
            }
        }
    }

    /// Sử dụng Apple Vision framework để nhận diện chữ trên ảnh (on-device hoàn toàn)
    private nonisolated func performVisionOCR(cgImage: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                guard error == nil, let observations = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let textLines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: textLines.joined(separator: "\n"))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let desired = ["en-US", "vi-VN", "ja-JP", "zh-Hans", "zh-Hant", "ko-KR", "fr-FR", "de-DE", "it-IT"]
            let supported = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]
            request.recognitionLanguages = desired.filter { supported.contains($0) }
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    private func handleRecognizedText(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            isCapturing = false
            return
        }

        self.lastOCRText = cleaned
        self.lastTranslatedText = ""
        self.sourceLanguage = Self.detectLanguage(cleaned) ?? .english
        self.targetLanguage = sourceLanguage == .vietnamese ? .english : .vietnamese
        notice = "Kiểm tra chữ và ngôn ngữ trước khi dịch."
        isCapturing = false
        showReview = true
    }

    nonisolated static func detectLanguage(_ text: String) -> AppLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let code = recognizer.dominantLanguage?.rawValue else { return nil }
        switch code {
        case "en": return .english
        case "vi": return .vietnamese
        case "ja": return .japanese
        case "zh-Hans", "zh-Hant", "zh": return .chinese
        case "ko": return .korean
        case "fr": return .french
        case "de": return .german
        case "it": return .italian
        default: return nil
        }
    }

    func translateReviewedText() async {
        guard !isTranslating, !lastOCRText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isTranslating = true; notice = "Đang dịch…"; lastTranslatedText = ""
        defer { isTranslating = false }
        let text = lastOCRText, source = sourceLanguage, target = targetLanguage
        if source == target { lastTranslatedText = text; notice = "Hai ngôn ngữ giống nhau."; return }
        if #available(macOS 15.0, *), let result = try? await AppleNativeTranslator.translate(text, from: source, to: target) {
            lastTranslatedText = result; notice = "Đã dịch bằng Apple trên máy."; return
        }
        if let model = MeetingModel.shared, let ai = model.configuredAI,
           let result = try? await AITranslator.translate(text, from: source, to: target, domain: model.domainSpecialty, provider: ai.provider, model: ai.model, key: ai.key) {
            lastTranslatedText = result; notice = "Đã dịch bằng \(ai.provider.shortName)."; return
        }
        do {
            lastTranslatedText = try await AITranslator.freeTranslate(text, from: source, to: target)
            notice = "Đã dịch bằng Google."
        } catch { notice = "Chưa dịch được. Kiểm tra kết nối và thử lại." }
    }
}

struct ScreenOCRReviewView: View {
    @ObservedObject private var service = ScreenOCRService.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Chụp & dịch màn hình", systemImage: "viewfinder").font(.title2.bold())
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Đóng xem trước OCR")
            }
            Text("Sửa chữ nhận diện và chọn ngôn ngữ trước khi dịch.").foregroundStyle(.secondary)
            HStack {
                Picker("Từ", selection: $service.sourceLanguage) { ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) } }
                Picker("Sang", selection: $service.targetLanguage) { ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) } }
            }.disabled(service.isTranslating)
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Chữ nhận diện").font(.headline)
                    TextEditor(text: $service.lastOCRText).font(.body).padding(8).background(.background).clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Nội dung OCR").disabled(service.isTranslating)
                }
                VStack(alignment: .leading) {
                    Text("Bản dịch").font(.headline)
                    ScrollView { Text(service.lastTranslatedText.isEmpty ? "Bản dịch sẽ hiện ở đây." : service.lastTranslatedText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                        .background(Color.secondary.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }.frame(height: 270)
            HStack {
                Text(service.notice).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !service.lastTranslatedText.isEmpty {
                    Button("Sao chép") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(service.lastTranslatedText, forType: .string) }
                }
                Button { Task { await service.translateReviewedText() } } label: { Label(service.isTranslating ? "Đang dịch…" : "Dịch", systemImage: "character.bubble") }
                    .buttonStyle(.borderedProminent).disabled(service.isTranslating || service.lastOCRText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 720)
    }
}
