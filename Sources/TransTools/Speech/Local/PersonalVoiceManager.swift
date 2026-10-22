import Foundation
import AVFoundation
import AppKit
import Speech
import LocalSpeechBackend

struct PersonalVoiceProfile: Codable, Identifiable {
    let id: UUID
    let name: String
    let created: Date
    let duration: Double
    var referenceText: String?
    var voiceID: String { "personal:" + id.uuidString }
}

@MainActor
final class PersonalVoiceManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = PersonalVoiceManager()
    nonisolated static var root: URL { ExternalTTSModel.root.deletingLastPathComponent().appendingPathComponent("PersonalVoices") }
    nonisolated static var encoder: URL { root.appendingPathComponent("Runtime/speaker_encoder.onnx") }
    @Published private(set) var revision = 0
    @Published private(set) var profiles: [PersonalVoiceProfile] = []
    @Published private(set) var modelProfiles: [UUID: Set<PersonalVoiceModel>] = [:]
    @Published private(set) var sizes: [UUID: Int64] = [:]
    @Published private(set) var recording = false
    @Published private(set) var processing = false
    @Published private(set) var ready = false
    @Published var status = ""
    @Published private(set) var checkingSpeech = false
    @Published private(set) var transcript = ""
    private var recognition: SFSpeechRecognitionTask?
    private var recognitionTimeout: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var samples: [Float] = []
    private let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("trans-tools-personal-" + UUID().uuidString + ".wav")
    static let defaultPrompt = "Buổi sáng, tôi mở cửa đón nắng, nghe tiếng chim và chuẩn bị một ngày mới thật vui."
    @Published private(set) var prompt = PersonalVoiceManager.defaultPrompt
    @Published private(set) var generatingScript = false
    @Published private(set) var recordedAt: Date?
    private var scriptTask: Task<Void, Never>?
    override private init() { super.init(); refresh() }
    func refresh() {
        revision += 1
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? []
        profiles = urls.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("profile.json")) else { return nil }
            return try? JSONDecoder().decode(PersonalVoiceProfile.self, from: data)
        }.sorted { $0.created > $1.created }
        modelProfiles = Dictionary(uniqueKeysWithValues: profiles.map { profile in
            (profile.id, Set(PersonalVoiceModel.allCases.filter { $0.existingFile(profile, root: Self.root) != nil }))
        })
        sizes = Dictionary(uniqueKeysWithValues: profiles.map { profile in
            let folder = Self.root.appendingPathComponent(profile.id.uuidString)
            let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
            var size: Int64 = 0
            while let url = files?.nextObject() as? URL {
                if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true { size += Int64(values.fileSize ?? 0) }
            }
            return (profile.id, size)
        })
    }
    func generateScript() {
        guard !recording, !processing, !checkingSpeech, !generatingScript else { return }
        guard let ai = MenuBarManager.shared.voiceScriptAI else {
            status = "Chưa cấu hình AI. Bạn vẫn có thể đọc đoạn mẫu có sẵn."; return
        }
        generatingScript = true; status = "AI đang chuẩn bị đoạn đọc mẫu…"
        scriptTask = Task { [weak self] in
            guard let self else { return }
            defer { generatingScript = false; scriptTask = nil }
            do {
                let request = """
                Viết đúng một đoạn tiếng Việt tự nhiên để người lớn thu giọng nói trong khoảng 6 đến 8 giây.
                Chỉ 18 đến 24 từ cách nhau bằng khoảng trắng, một hoặc hai câu ngắn, đa dạng dấu thanh.
                Chủ đề đời sống nhẹ nhàng, không tên riêng, số, viết tắt, lời quảng cáo hoặc nội dung nhạy cảm.
                Chỉ trả về đoạn văn, không tiêu đề, không Markdown hay giải thích.
                """
                let text = try await AITransport.complete(prompt: request, provider: ai.provider, model: ai.model, key: ai.key, timeout: 20)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                try Task.checkCancellation()
                guard Self.validScript(text) else { status = "Đoạn AI chưa phù hợp thời lượng. Giữ mẫu hiện tại; bạn có thể thử lại."; return }
                prompt = text; ready = false; samples = []; transcript = ""
                try? FileManager.default.removeItem(at: scratch)
                status = "Đã có đoạn mới. Đọc thử một lần trước khi thu."
            } catch { if !Task.isCancelled { status = "Chưa tạo được đoạn AI. Bạn có thể dùng mẫu có sẵn." } }
        }
    }
    static func validScript(_ text: String) -> Bool {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        return (18...24).contains(words.count) && text.count <= 240 && !text.contains("\n")
            && text.rangeOfCharacter(from: .decimalDigits) == nil && !text.contains("#") && !text.contains("*")
    }
    func start() async {
        guard !processing, !recording, !checkingSpeech, !generatingScript, !MenuBarManager.shared.meetingRunning, !ConversationController.shared.active else { status = "Kết thúc cuộc họp hoặc trò chuyện trước khi thu giọng."; return }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { status = "Cần cấp quyền microphone để thu giọng."; return }
        guard !Task.isCancelled, !MenuBarManager.shared.meetingRunning, !ConversationController.shared.active else { return }
        do {
            player?.stop(); ready = false; samples = []; transcript = ""
            recorder = try AVAudioRecorder(url: scratch, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
            recorder?.delegate = self
            guard recorder?.record(forDuration: 8) == true else { throw URLError(.cannotCreateFile) }
            recordedAt = Date(); recording = true; status = "Đọc đoạn mẫu tự nhiên. Tự dừng sau 8 giây."
        } catch { status = error.localizedDescription }
    }
    func stop() { recorder?.stop(); recording = false; inspect() }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.recording = false; if flag { self.inspect() } else { self.status = "Thu âm chưa hoàn tất. Hãy thu lại." } }
    }
    private func inspect() {
        do {
            let file = try AVAudioFile(forReading: scratch)
            guard file.length >= 48000, file.length <= 128000,
                  let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                status = "Hãy thu từ 3 đến 8 giây, đọc liên tục và rõ."; return
            }
            try file.read(into: buffer)
            guard let channel = buffer.floatChannelData?[0] else { throw URLError(.cannotDecodeContentData) }
            samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            let rms = sqrt(samples.reduce(0) { $0 + Double($1*$1) } / Double(samples.count))
            let clipped = samples.filter { abs($0) >= 0.98 }.count
            guard rms > 0.008, clipped < samples.count / 100 else {
                ready = false; status = "Bản thu quá nhỏ hoặc bị vỡ tiếng. Hãy chỉnh khoảng cách microphone và thu lại."; return
            }
            ready = true; status = "Âm lượng đạt yêu cầu. Nghe lại để kiểm tra tiếng ồn và đọc đủ đoạn mẫu trước khi tạo giọng."
        } catch { ready = false; status = error.localizedDescription }
    }
    func preview() {
        do { player = try AVAudioPlayer(contentsOf: scratch); player?.play() }
        catch { status = error.localizedDescription }
    }
    func checkWords() async {
        guard ready, !checkingSpeech, !recording, !processing else { return }
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard authorization == .authorized, let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN")), recognizer.supportsOnDeviceRecognition else {
            status = "Nhận diện tiếng Việt trên thiết bị chưa khả dụng hoặc chưa được cấp quyền. Hãy nghe lại để kiểm tra lời đọc."; return
        }
        checkingSpeech = true; transcript = ""; status = "Đang kiểm tra lời đọc trên thiết bị…"
        let request = SFSpeechURLRecognitionRequest(url: scratch)
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = false
        recognition = recognizer.recognitionTask(with: request) { result, error in
            Task { @MainActor in
                guard self.checkingSpeech else { return }
                if let result, result.isFinal {
                    self.transcript = result.bestTranscription.formattedString
                    let normalize: (String) -> [String] = { text in
                        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi-VN"))
                            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
                    }
                    let expected = normalize(self.prompt), actual = normalize(self.transcript)
                    var previous = [Int](repeating: 0, count: actual.count + 1)
                    for word in expected {
                        var next = previous
                        for j in actual.indices {
                            next[j + 1] = word == actual[j] ? previous[j] + 1 : max(previous[j + 1], next[j])
                        }
                        previous = next
                    }
                    self.status = (previous.last ?? 0) * 100 >= expected.count * 85
                        ? "Lời đọc nhận diện gần khớp mẫu. Hãy nghe lại để xác nhận chất lượng."
                        : "Lời đọc có thể thiếu chữ hoặc nhận diện chưa đúng. Xem nội dung nhận diện, nghe lại và thu lại nếu cần."
                    self.finishRecognition()
                } else if error != nil {
                    self.status = "Chưa kiểm tra được lời đọc trên thiết bị. Bạn vẫn có thể nghe lại bản thu."; self.finishRecognition()
                }
            }
        }
        recognitionTimeout = Task {
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            guard checkingSpeech else { return }
            status = "Kiểm tra lời đọc quá thời gian. Hãy nghe lại bản thu."; finishRecognition()
        }
    }
    private func finishRecognition() {
        checkingSpeech = false; recognition?.cancel(); recognition = nil
        recognitionTimeout?.cancel(); recognitionTimeout = nil
    }
    func create(name: String) async {
        guard ready, !processing, !recording, !checkingSpeech else { return }
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let profile = PersonalVoiceProfile(id: UUID(), name: String((trimmed.isEmpty ? "Giọng của tôi" : trimmed).prefix(40)), created: Date(), duration: Double(samples.count)/16000, referenceText: prompt)
            let directory = Self.root.appendingPathComponent(profile.id.uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            do {
                try FileManager.default.copyItem(at: scratch, to: directory.appendingPathComponent("reference.wav"))
                try JSONEncoder().encode(profile).write(to: directory.appendingPathComponent("profile.json"), options: .atomic)
            } catch { try? FileManager.default.removeItem(at: directory); throw error }
            refresh(); ready = false; samples = []
            status = "Đã lưu bản thu gốc. Chọn mô hình tương thích để tạo hồ sơ giọng."
        } catch { status = "Chưa lưu được bản thu: " + error.localizedDescription }
    }
    func createModel(_ profile: PersonalVoiceProfile, model: PersonalVoiceModel) async {
        guard !processing, !recording, !checkingSpeech, !MenuBarManager.shared.meetingRunning, !ConversationController.shared.active,
              model.isInstalled, !hasModel(profile, model: model) else { return }
        processing = true; defer { processing = false }
        do {
            player?.stop()
            status = "Đang tạo hồ sơ " + model.title + " · bộ trích xuất chỉ tải lần đầu…"
            let reference = Self.root.appendingPathComponent(profile.id.uuidString).appendingPathComponent("reference.wav")
            let snapshot = try await Task.detached(priority: .userInitiated) {
                let file = try AVAudioFile(forReading: reference)
                guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
                      file.length >= 48000, file.length <= 128000,
                      let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw URLError(.cannotDecodeContentData) }
                try file.read(into: buffer)
                guard let channel = buffer.floatChannelData?[0] else { throw URLError(.cannotDecodeContentData) }
                return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            }.value
            let vector = try await Task.detached(priority: .userInitiated) {
                let encoder = Self.encoder
                let artifact = LocalTTSModelFile(path: "speaker_encoder.onnx", size: 28303423, sha256: "a6ac6a63997761ae2997373e2ee1c47040854b4b759ea41ec48e4e42df0f4d73")
                if (try? LocalTTSModelStore.verify(encoder, file: artifact)) == nil {
                    let url = URL(string: "https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/61b85e3d937fbbacb387714180e8182823512523/speaker_encoder.onnx")!
                    let (temporary, response) = try await URLSession.shared.download(from: url)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    try LocalTTSModelStore.verify(temporary, file: artifact)
                    try FileManager.default.createDirectory(at: encoder.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: encoder.path) { try FileManager.default.removeItem(at: encoder) }
                    try FileManager.default.moveItem(at: temporary, to: encoder)
                }
                return try VieNeuSpeakerEncoder.extract(samples: snapshot, encoder: encoder)
            }.value
            let destination = model.file(profile, root: Self.root)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["speaker_emb": vector]).write(to: destination, options: .atomic)
            refresh(); status = "Đã tạo hồ sơ " + model.title + ". Đọc thử câu mới trước khi chọn dùng."
        } catch { status = "Chưa tạo được hồ sơ: " + error.localizedDescription }
    }
    func hasModel(_ profile: PersonalVoiceProfile, model: PersonalVoiceModel = .vieneu) -> Bool {
        modelProfiles[profile.id]?.contains(model) == true
    }
    func previewOriginal(_ profile: PersonalVoiceProfile) {
        do {
            TTSService.shared.stop(); player?.stop()
            player = try AVAudioPlayer(contentsOf: Self.root.appendingPathComponent(profile.id.uuidString).appendingPathComponent("reference.wav"))
            player?.play(); status = "Đang nghe bản thu gốc · " + profile.name
        } catch { status = "Không mở được bản thu: " + error.localizedDescription }
    }
    func stopPlayback() { player?.stop() }
    func rename(_ profile: PersonalVoiceProfile, name: String) {
        let value = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !value.isEmpty, !processing, !recording else { return }
        do {
            let updated = PersonalVoiceProfile(id: profile.id, name: value, created: profile.created, duration: profile.duration, referenceText: profile.referenceText)
            try JSONEncoder().encode(updated).write(to: Self.root.appendingPathComponent(profile.id.uuidString).appendingPathComponent("profile.json"), options: .atomic)
            refresh(); status = "Đã đổi tên bản thu."
        } catch { status = error.localizedDescription }
    }
    func removeModel(_ profile: PersonalVoiceProfile, model: PersonalVoiceModel) {
        guard !processing, !recording else { return }
        player?.stop()
        let files = [model.file(profile, root: Self.root), Self.root.appendingPathComponent(profile.id.uuidString).appendingPathComponent("voice.json")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        NSWorkspace.shared.recycle(files) { _, error in
            Task { @MainActor in
                if error == nil { self.resetSelection(profile) }
                self.refresh(); self.status = error?.localizedDescription ?? "Đã gỡ hồ sơ mô hình; giữ nguyên bản thu gốc."
            }
        }
    }
    private func resetSelection(_ profile: PersonalVoiceProfile) {
        if UserDefaults.standard.string(forKey: "TTS_vieneu_Voice_vi") == profile.voiceID {
            UserDefaults.standard.removeObject(forKey: "TTS_vieneu_Voice_vi")
        }
    }
    func test(_ profile: PersonalVoiceProfile) async {
        guard !processing, !MenuBarManager.shared.meetingRunning, !ConversationController.shared.active, hasModel(profile), ExternalTTSModel.vieneu.isInstalled else { return }
        processing = true; defer { processing = false }
        do {
            player?.stop()
            TTSService.shared.stop()
            await LocalTTSSession.shared.releaseAndWait()
            let result = try await NativeVieNeu.shared.synthesize(text: "Ngày mai tôi sẽ dành thời gian đọc sách và luyện nói tiếng Việt rõ ràng hơn.", voice: profile.voiceID, options: .default, onChunk: nil)
            player = try AVAudioPlayer(data: result.audioData); player?.play()
            status = "Đang nghe câu mới bằng giọng cá nhân."
        } catch { status = error.localizedDescription }
    }
    func use(_ profile: PersonalVoiceProfile) {
        guard hasModel(profile), ExternalTTSModel.vieneu.isInstalled else { return }
        player?.stop()
        TTSService.shared.stop()
        UserDefaults.standard.set(profile.voiceID, forKey: "TTS_vieneu_Voice_vi")
        LanguageVoicePreferences.set(.vieneu, for: "vi")
        revision += 1
    }
    func remove(_ profile: PersonalVoiceProfile) {
        guard !processing, !recording else { return }
        player?.stop()
        NSWorkspace.shared.recycle([Self.root.appendingPathComponent(profile.id.uuidString)]) { _, error in
            Task { @MainActor in
                self.status = error?.localizedDescription ?? "Đã chuyển giọng vào Thùng rác."
                if error == nil && UserDefaults.standard.string(forKey: "TTS_vieneu_Voice_vi") == profile.voiceID {
                    UserDefaults.standard.removeObject(forKey: "TTS_vieneu_Voice_vi")
                }
                self.refresh()
            }
        }
    }
    func cancelRecording() {
        scriptTask?.cancel(); finishRecognition(); recorder?.delegate = nil; recorder?.stop(); player?.stop(); recording = false
        if !processing { samples = []; ready = false; try? FileManager.default.removeItem(at: scratch) }
    }
}
