import SwiftUI
import AppKit

struct StorageEntry: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let url: URL
    let removable: Bool
    let model: Bool
    var bytes: Int64 = 0
    var files = 0
    var exists = false
    var scanError: String?
}

enum StorageInventory {
    static func scan(_ entries: [StorageEntry]) -> [StorageEntry] {
        entries.map { entry in
            var result = entry
            let fm = FileManager.default
            result.exists = fm.fileExists(atPath: entry.url.path)
            guard result.exists else { return result }
            do {
                let root = try entry.url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                guard root.isSymbolicLink != true else { result.scanError = "Đường dẫn liên kết · không hỗ trợ dọn"; return result }
                if root.isDirectory != true {
                    result.bytes = Int64(root.fileSize ?? 0); result.files = 1
                    return result
                }
                let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                var enumerationFailed = false
                guard let iterator = fm.enumerator(at: entry.url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in enumerationFailed = true; return false }) else {
                    result.scanError = "Không đọc được thư mục"; return result
                }
                for case let file as URL in iterator {
                    let values = try file.resourceValues(forKeys: Set(keys))
                    if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
                    if values.isRegularFile == true { result.bytes += Int64(values.fileSize ?? 0); result.files += 1 }
                }
                if enumerationFailed { result.scanError = "Không đọc được đầy đủ dung lượng" }
            } catch { result.scanError = "Không đọc được đầy đủ dung lượng" }
            return result
        }
    }
}

struct StorageSettingsView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject private var tts = TTSService.shared
    @ObservedObject private var router = TTSEngineRouter.shared
    @ObservedObject private var external = ExternalTTSModelManager.shared
    @ObservedObject private var local = LocalTTSModelManager.shared
    @State private var entries: [StorageEntry] = []
    @State private var scanning = false
    @State private var cleaning = false
    @State private var pending: StorageEntry?
    @State private var message = ""
    private var busy: Bool {
        if model.running || tts.isSpeaking || router.isProcessing || cleaning || external.installing != nil { return true }
        switch local.state { case .downloading, .verifying: return true; default: return false }
    }
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    private var definitions: [StorageEntry] {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TransTools")
        let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return [
            StorageEntry(id: "voice", title: "Supertonic 3 · Local", detail: local.isInstalled ? "Đã cài · gồm dữ liệu Supertonic đã tải. Gỡ sẽ chuyển về giọng cơ bản." : "Chưa cài hoặc còn dữ liệu tải Supertonic. Có thể tải lại khi cần.", url: support.appendingPathComponent("Models/TTS"), removable: true, model: true),
            StorageEntry(id: "external-vieneu", title: "VieNeu-TTS v3 Turbo", detail: "Dữ liệu mô hình và từ điển phát âm. Bộ xử lý native có sẵn trong app; không cần SDK Python.", url: ExternalTTSModel.vieneu.directory, removable: true, model: true),
            StorageEntry(id: "external-qwen", title: "Qwen3-TTS 0.6B", detail: "Trọng số MLX và speech tokenizer. Gỡ sẽ dùng giọng dự phòng cho ngôn ngữ đang chọn.", url: ExternalTTSModel.qwen.directory, removable: true, model: true),
            StorageEntry(id: "qwen-runtime", title: "Bộ xử lý Qwen", detail: "Chỉ cần khi dùng Qwen. VieNeu và Supertonic dùng bộ xử lý native có sẵn trong app.", url: ExternalTTSModel.root.appendingPathComponent("Environments/qwen"), removable: true, model: true),
            StorageEntry(id: "external-logs", title: "Nhật ký cài giọng Local", detail: "Thông tin SDK và tải mô hình; không lưu nội dung đọc.", url: ExternalTTSModel.root.appendingPathComponent("Logs"), removable: true, model: false),
            StorageEntry(id: "external-python", title: "Python cho Qwen", detail: "Chỉ dùng cho Qwen. VieNeu và Supertonic không cần Python. Có thể tải lại khi cài Qwen.", url: ExternalTTSModel.root.appendingPathComponent("Python"), removable: true, model: true),
            StorageEntry(id: "edge", title: "Cache giọng trực tuyến", detail: "Audio Edge đã tạo. Dọn cache sẽ cần tạo lại audio khi nghe tiếp.", url: cache.appendingPathComponent("TransToolsEdgeTTS"), removable: true, model: false),
            StorageEntry(id: "strokes", title: "Cache hướng dẫn nét viết", detail: "Ảnh hướng dẫn đã tải. Có thể tải lại khi mở bài học.", url: cache.appendingPathComponent("TransTools/NHKStrokes"), removable: true, model: false),
            StorageEntry(id: "english", title: "Phát âm tiếng Anh · Offline", detail: "Bản ghi đã tải. Xóa sẽ làm mất khả năng nghe offline của bộ này.", url: support.appendingPathComponent("Pronunciation/AudioLangEnglish"), removable: true, model: false),
            StorageEntry(id: "japanese", title: "Phát âm tiếng Nhật · Offline", detail: "Bản ghi đã tải. Cần tải lại để nghe bộ này sau khi xóa.", url: support.appendingPathComponent("Pronunciation/NHKJapanese"), removable: true, model: false),
            StorageEntry(id: "chinese", title: "Phát âm tiếng Trung · Offline", detail: "Bản ghi đã tải. Cần tải lại để nghe bộ này sau khi xóa.", url: support.appendingPathComponent("Pronunciation/ZIMChinese"), removable: true, model: false),
            StorageEntry(id: "notebook", title: "Sổ tay & Hội thoại", detail: "Dữ liệu cá nhân được bảo vệ. Quản lý từng buổi trong Sổ tay hoặc Trò chuyện.", url: support.appendingPathComponent("meeting_sessions.json"), removable: false, model: false),
            StorageEntry(id: "bundled", title: "Học liệu đi kèm ứng dụng", detail: "Tài nguyên trong app, không dọn riêng. Bao gồm hình Chip Chip và bản ghi có sẵn.", url: Bundle.main.resourceURL ?? Bundle.main.bundleURL, removable: false, model: false)
        ]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(size(entries.reduce(0) { $0 + $1.bytes })).font(.system(size: 28, weight: .bold))
                    Text("Dung lượng tệp của các nhóm bên dưới").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if scanning { ProgressView().controlSize(.small) }
                Button { refresh() } label: { Label("Làm mới", systemImage: "arrow.clockwise") }
                    .buttonStyle(SettingsActionButtonStyle()).disabled(scanning || cleaning)
            }
            .padding(20).background(TransToolsTheme.mint, in: RoundedRectangle(cornerRadius: 14))
            Text("Dọn từng nhóm sẽ chuyển dữ liệu vào Thùng rác. Sổ tay, từ vựng và API key không bị xóa khi dọn cache. Dung lượng ổ đĩa được giải phóng sau khi bạn làm trống Thùng rác.")
                .font(.callout).foregroundStyle(.secondary)
            if busy { Label("Dừng phiên đang chạy, phần đọc hoặc tải mô hình trước khi dọn.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title).font(.headline)
                        Text(entry.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(entry.scanError ?? (entry.exists ? "\(size(entry.bytes)) · \(entry.files) tệp" : "Chưa có dữ liệu"))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button("Xem thư mục") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                        .buttonStyle(SettingsActionButtonStyle()).disabled(!entry.exists)
                    if entry.removable {
                        Button(entry.model ? "Gỡ mô hình" : "Dọn", role: .destructive) { pending = entry }
                            .buttonStyle(SettingsActionButtonStyle()).disabled(busy || scanning || !entry.exists || entry.scanError != nil)
                    }
                }
                .padding(18).transToolsPanel()
            }
            Text("Từ vựng: \(size(Int64(UserDefaults.standard.data(forKey: "TransTools_SavedVocabulary_v1")?.count ?? 0))) dữ liệu từ vựng. Được giữ riêng, không thuộc thao tác dọn.")
                .font(.caption).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.secondary) }
        }
        .task { refresh() }
        .confirmationDialog("Dọn \(pending?.title ?? "dữ liệu")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Chuyển vào Thùng rác", role: .destructive) {
                if let entry = pending { clean(entry) }; pending = nil
            }
            Button("Hủy", role: .cancel) { pending = nil }
        } message: { Text("\(pending?.detail ?? "") Có thể khôi phục từ Thùng rác. Với học liệu đã tải, hãy mở lại app sau khi khôi phục.") }
    }
    private func refresh() {
        guard !scanning else { return }
        scanning = true
        let snapshot = definitions
        Task {
            let scanned = await Task.detached(priority: .utility) { StorageInventory.scan(snapshot) }.value
            // Empty optional groups have nothing to manage. Keep failed scans
            // visible so inaccessible data is not mistaken for absent data.
            entries = scanned.filter { !$0.removable || $0.files > 0 || $0.scanError != nil }
            scanning = false
        }
    }
    private func clean(_ entry: StorageEntry) {
        guard !busy, definitions.contains(where: { $0.id == entry.id && $0.url == entry.url && $0.removable }) else { return }
        cleaning = true; message = "Đang chuyển dữ liệu vào Thùng rác…"
        let restoreNaturalVoice = local.isNaturalVoiceEnabled
        if entry.id == "voice" { local.isNaturalVoiceEnabled = false }
        Task {
            if entry.id.hasPrefix("external-") || entry.id == "qwen-runtime" { await ExternalTTSSession.shared.releaseAndWait() }
            NSWorkspace.shared.recycle([entry.url]) { _, error in
            Task { @MainActor in
                cleaning = false
                if let error {
                    message = "Chưa dọn được: \(error.localizedDescription)"
                    if entry.id == "voice" { local.isNaturalVoiceEnabled = restoreNaturalVoice }
                }
                else {
                    message = "Đã chuyển \(entry.title) vào Thùng rác."
                    if entry.id == "voice" { local.checkInstallation() }
                    if entry.id.hasPrefix("external-") || entry.id == "qwen-runtime" { external.refresh() }
                    if entry.id == "strokes" { NHKStrokeGuideService.shared.clearMemoryCache() }
                    if entry.id == "edge" { await EdgeTTSService.shared.clearMemoryCache() }
                }
                refresh()
            }
        }
        }
    }
}
