import Foundation
import Metal

/// Catalog data is trusted application data, never executable remote repository metadata.
enum AIModelCategory: String, Codable, CaseIterable, Sendable { case tts, stt, translation, languageModel }
enum AIModelFeature: String, Codable, Sendable { case textToSpeech, speechRecognition, translation, languageGeneration }
enum AIModelInstallationState: Equatable, Sendable {
    case notInstalled, queued, downloading(Double), paused, verifying, installing
    case installed, updateAvailable, loading, ready, failed(String), incompatible(String)
    var title: String {
        switch self {
        case .notInstalled: return "Chưa cài"
        case .queued: return "Đang chờ"
        case .downloading: return "Đang tải"
        case .paused: return "Đã tạm dừng"
        case .verifying: return "Đang xác minh"
        case .installing: return "Đang cài"
        case .installed: return "Đã cài"
        case .updateAvailable: return "Có bản mới"
        case .loading: return "Đang nạp"
        case .ready: return "Sẵn sàng"
        case .failed: return "Chưa hoàn tất"
        case .incompatible: return "Không tương thích"
        }
    }
}
enum ModelSource: Sendable {
    case huggingFace(repository: String, revision: String, path: String)
    case direct(URL)
    case bundled(path: String)
    func url(bundle: Bundle = .main) throws -> URL {
        switch self {
        case let .huggingFace(repository, revision, path):
            guard repository.split(separator: "/").count == 2, ModelArtifact.safePath(repository), ModelArtifact.safePath(revision), ModelArtifact.safePath(path),
                  let url = URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(path)") else { throw ModelManagerError.invalidArtifact }
            return url
        case let .direct(url):
            guard url.scheme == "https", url.user == nil, url.password == nil else { throw ModelManagerError.invalidArtifact }; return url
        case let .bundled(path):
            guard ModelArtifact.safePath(path), let root = bundle.resourceURL else { throw ModelManagerError.invalidArtifact }
            return root.appendingPathComponent(path)
        }
    }
}
struct ModelArtifact: Sendable {
    let path: String
    let source: ModelSource
    let bytes: Int64
    let sha256: String
    static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("%") && !path.contains(":" ) && !path.unicodeScalars.contains(where: { $0.value < 32 }) && !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }
}
struct ModelCapabilities: Sendable {
    let offline: Bool
    let voiceCloning: Bool
    let streaming: Bool
}
struct ModelRuntimeRequirement: Sendable {
    let id: String
    let name: String
    let minimumOSMajor: Int
    let appleSiliconOnly: Bool
    /// Advisory, never a fabricated benchmark or hard incompatibility rule.
    let recommendedRAMBytes: UInt64?
}
protocol AIModel: Identifiable, Sendable {
    var id: String { get }
    var engineID: String { get }
    var languages: [String] { get }
}
struct AIModelDescriptor: AIModel {
    let id: String
    let name: String
    let summary: String
    let category: AIModelCategory
    let engineID: String
    let version: String
    let languages: [String]
    let requiredFiles: [ModelArtifact]
    let optionalFiles: [ModelArtifact]
    let runtime: ModelRuntimeRequirement
    let capabilities: ModelCapabilities
    let license: String
    let recommended: Bool
    let dependencies: [String]
    var downloadBytes: Int64 { requiredFiles.reduce(0) { $0 + $1.bytes } }
}
enum ModelCompatibility: Equatable, Sendable { case recommended, compatible, notRecommended(String), incompatible(String) }
struct HardwareCapabilities: Sendable {
    let appleSilicon: Bool
    let logicalCPUs: Int
    let ramBytes: UInt64
    let osMajor: Int
    let metalAvailable: Bool
    /// Public APIs do not reliably enumerate Neural Engine availability.
    let neuralEngineAvailable: Bool? = nil
    static func detect() -> Self {
        #if arch(arm64)
        let silicon = true
        #else
        let silicon = false
        #endif
        let process = ProcessInfo.processInfo
        return Self(appleSilicon: silicon, logicalCPUs: process.activeProcessorCount, ramBytes: process.physicalMemory,
                    osMajor: process.operatingSystemVersion.majorVersion, metalAvailable: MTLCreateSystemDefaultDevice() != nil)
    }
    func compatibility(_ model: AIModelDescriptor) -> ModelCompatibility {
        if osMajor < model.runtime.minimumOSMajor { return .incompatible("Cần hệ điều hành phiên bản \(model.runtime.minimumOSMajor) trở lên.") }
        if model.runtime.appleSiliconOnly && !appleSilicon { return .incompatible("Bộ xử lý này chỉ hỗ trợ Apple Silicon.") }
        if let ram = model.runtime.recommendedRAMBytes, ramBytes < ram { return .notRecommended("RAM thấp hơn mức khuyến nghị; vẫn có thể cài.") }
        return model.recommended ? .recommended : .compatible
    }
}
enum ModelManagerError: LocalizedError {
    case invalidArtifact, unsupportedModel, inUse, missingFiles, insufficientSpace, invalidAudio
    var errorDescription: String? {
        switch self {
        case .invalidArtifact: return "Manifest hoặc đường dẫn mô hình không hợp lệ."
        case .unsupportedModel: return "Chưa tích hợp bộ xử lý cho mô hình này."
        case .inUse: return "Dừng phần đọc, thu âm và cuộc trò chuyện trước khi thay đổi mô hình."
        case .missingFiles: return "Mô hình thiếu tệp hoặc dữ liệu bị hỏng."
        case .insufficientSpace: return "Không đủ dung lượng để tải và cài an toàn."
        case .invalidAudio: return "Mô hình không tạo được audio hợp lệ."
        }
    }
}
struct LanguagePack: Identifiable, Sendable {
    let id: String
    let name: String
    let language: String
    let modelIDs: [String]
}
struct ModelRegistry: Sendable {
    let models: [AIModelDescriptor]
    let packs: [LanguagePack]
    func model(_ id: String) -> AIModelDescriptor? { models.first { $0.id == id } }
    func installationOrder(for packID: String) throws -> [String] {
        guard let pack = packs.first(where: { $0.id == packID }) else { throw ModelManagerError.unsupportedModel }
        var ordered: [String] = [], visiting = Set<String>(), visited = Set<String>()
        func visit(_ id: String) throws {
            guard !visiting.contains(id), let descriptor = model(id) else { throw ModelManagerError.invalidArtifact }
            guard !visited.contains(id) else { return }
            visiting.insert(id)
            for dependency in descriptor.dependencies { try visit(dependency) }
            visiting.remove(id); visited.insert(id); ordered.append(id)
        }
        for id in pack.modelIDs { try visit(id) }
        return ordered
    }
    static func current() throws -> Self {
        let supertonic = LocalTTSModelManifest.default
        let vie = try NativeVieNeuManifest.load()
        let runtime = ModelRuntimeRequirement(id: "onnx-native", name: "ONNX · Native", minimumOSMajor: 14, appleSiliconOnly: false, recommendedRAMBytes: nil)
        let models = [
            AIModelDescriptor(id: supertonic.id, name: "Supertonic 3", summary: "Giọng đọc đa ngôn ngữ, chạy trên thiết bị.", category: .tts, engineID: "supertonic", version: supertonic.version, languages: supertonic.supportedLanguages,
                requiredFiles: supertonic.files.map { ModelArtifact(path: $0.path, source: .huggingFace(repository: "supertone-oss-archive/supertonic-3", revision: supertonic.revision, path: $0.path), bytes: $0.size, sha256: $0.sha256) }, optionalFiles: [], runtime: runtime,
                capabilities: ModelCapabilities(offline: true, voiceCloning: false, streaming: false), license: "Open RAIL-M", recommended: true, dependencies: []),
            AIModelDescriptor(id: "vieneu-v3-turbo", name: "VieNeu-TTS v3 Turbo", summary: "Tiếng Việt tự nhiên, hỗ trợ hồ sơ giọng từ mẫu.", category: .tts, engineID: "vieneu", version: vie.version, languages: ["vi"],
                requiredFiles: vie.files.map { ModelArtifact(path: $0.path, source: .direct($0.url), bytes: $0.size, sha256: $0.sha256) }, optionalFiles: [], runtime: runtime,
                capabilities: ModelCapabilities(offline: true, voiceCloning: true, streaming: true), license: "Apache-2.0", recommended: true, dependencies: [])
        ]
        return Self(models: models, packs: [LanguagePack(id: "vi-speech", name: "Giọng đọc tiếng Việt", language: "vi", modelIDs: models.map(\.id))])
    }
}
