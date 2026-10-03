import Foundation
import AVFoundation

/// Basic lessons only play recordings. Missing recordings open the publisher;
/// speech synthesis must never be substituted for a letter or isolated sound.
final class LanguagePronunciationService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = LanguagePronunciationService()
    @Published var isSpeaking = false
    @Published var isPlayingSequence = false
    @Published var currentText: String?
    @Published var currentIndex: Int?
    @Published var sourceRequired = false
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var queue: [String] = []
    private var timer: Timer?
    private var generation = UUID()
    private var progress: ((Int) -> Void)?
    private var finished: (() -> Void)?
    private var sequenceLanguage: LearningLanguage = .english
    private var delay: TimeInterval = 0.5

    func speak(text: String, language: LearningLanguage, british: Bool = false, rate: Float = 0.44) {
        stop()
        guard let file = recording(text, language: language) else {
            if language == .japanese || language == .chinese { error = "Chưa có bản ghi offline cho nội dung này." } else { sourceRequired = true }
            return
        }
        play(file, text: text)
    }

    func playSequence(items: [String], language: LearningLanguage, british: Bool = false,
                      rate: Float = 0.44, delay: TimeInterval = 0.5,
                      onProgress: ((Int) -> Void)? = nil, onFinished: (() -> Void)? = nil) {
        stop()
        guard !items.isEmpty else { return }
        guard items.allSatisfy({ recording($0, language: language) != nil }) else {
            if language == .japanese || language == .chinese { error = "Bộ bản ghi offline chưa đầy đủ. Không phát thay bằng giọng hệ thống." } else { sourceRequired = true }
            return
        }
        sequenceLanguage = language
        queue = items
        progress = onProgress
        finished = onFinished
        self.delay = delay
        isPlayingSequence = true
        next(0)
    }

    private func recording(_ text: String, language: LearningLanguage) -> URL? {
        switch language {
        case .english: return LocalEnglishRecordings.file(for: text)
        case .japanese: return LocalJapaneseRecordings.file(for: text)
        case .chinese: return LocalChineseRecordings.file(for: text)
        default: return nil
        }
    }

    private func next(_ index: Int) {
        guard index < queue.count, let file = recording(queue[index], language: sequenceLanguage) else {
            let completion = finished
            stop()
            completion?()
            return
        }
        currentIndex = index
        progress?(index)
        play(file, text: queue[index])
    }

    private func play(_ file: URL, text: String) {
        do {
            let audio = try AVAudioPlayer(contentsOf: file)
            audio.delegate = self
            audio.prepareToPlay()
            guard audio.play() else { throw NSError(domain: "Playback", code: 1) }
            player = audio
            currentText = text
            isSpeaking = true
        } catch {
            stop()
            self.error = "Không phát được bản ghi. Hãy thử lại hoặc mở nguồn học."
        }
    }

    func stop() {
        generation = UUID()
        timer?.invalidate(); timer = nil
        player?.stop(); player = nil
        isSpeaking = false; isPlayingSequence = false
        currentText = nil; currentIndex = nil
        queue = []; progress = nil; finished = nil
        sourceRequired = false; error = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard self.player === player else { return }
        isSpeaking = false
        if isPlayingSequence, let index = currentIndex {
            let token = generation
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self, self.generation == token else { return }
                self.next(index + 1)
            }
        } else {
            currentText = nil
            self.player = nil
        }
    }
}
