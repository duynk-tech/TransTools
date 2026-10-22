import SwiftUI
import AppKit

struct PersonalVoiceSettingsView: View {
    @ObservedObject private var manager = PersonalVoiceManager.shared
    @ObservedObject private var tts = TTSService.shared
    @ObservedObject private var conversation = ConversationController.shared
    @ObservedObject private var router = TTSEngineRouter.shared
    @State private var showRecorder = false
    @State private var removing: PersonalVoiceProfile?
    @State private var removingModel: PersonalVoiceProfile?
    @State private var renaming: PersonalVoiceProfile?
    @State private var draftName = ""
    @State private var query = ""
    private var visibleProfiles: [PersonalVoiceProfile] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? manager.profiles : manager.profiles.filter { $0.name.localizedStandardContains(value) }
    }
    private var busy: Bool { tts.isSpeaking || router.isProcessing || manager.processing || manager.checkingSpeech || manager.generatingScript || manager.recording || conversation.active || MenuBarManager.shared.meetingRunning }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Thư viện giọng cá nhân").font(.headline)
                        Text("Một bản thu gốc, nhiều hồ sơ theo mô hình hỗ trợ. Dữ liệu giữ trên thiết bị.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showRecorder = true } label: { Label("Thu giọng mới", systemImage: "mic.fill") }
                        .buttonStyle(TransToolsActionButtonStyle(prominent: true)).disabled(busy)
                }
                HStack(spacing: 18) {
                    Label("\(manager.profiles.count) bản thu", systemImage: "waveform")
                    Label(ByteCountFormatter.string(fromByteCount: manager.sizes.values.reduce(0, +), countStyle: .file), systemImage: "internaldrive")
                    Label("Lưu trên thiết bị", systemImage: "lock.shield")
                }.font(.caption).foregroundStyle(TransToolsTheme.accent)
            }.padding(18).transToolsPanel()

            VStack(alignment: .leading, spacing: 8) {
                Text("Mô hình tương thích").font(.headline)
                Text("VieNeu-TTS v3 Turbo · Tiếng Việt · Mẫu 3–8 giây")
                    .font(.subheadline).foregroundStyle(TransToolsTheme.accent)
                Text("Chỉ mô hình đã tích hợp khả năng tạo giọng mới xuất hiện ở đây. Hồ sơ đã xử lý thuộc từng mô hình; bản thu gốc có thể dùng lại. Cài mô hình trong Giọng đọc & Phát âm → Nâng cao.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16).background(TransToolsTheme.mint.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            if manager.profiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "mic.badge.plus").font(.system(size: 30)).foregroundStyle(TransToolsTheme.accent)
                    Text("Bắt đầu với giọng của bạn").font(.headline)
                    Text("Thu một đoạn ngắn, nghe lại và lưu. Tạo hồ sơ mô hình khi bạn cần sử dụng.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(30).transToolsPanel()
            }
            if !manager.profiles.isEmpty {
                TextField("Tìm bản thu theo tên…", text: $query).textFieldStyle(.roundedBorder)
                if visibleProfiles.isEmpty { Text("Không có bản thu phù hợp.").foregroundStyle(.secondary) }
            }
            ForEach(visibleProfiles) { profile in
                recordingCard(profile)
            }
            if manager.processing { ProgressView().controlSize(.small) }
            if !manager.status.isEmpty {
                Text(manager.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Nghe bản thu để xác nhận tiếng ồn và lời đọc. VieNeu hiện dùng đặc trưng người nói; chưa sao chép đầy đủ phong cách và chưa có huấn luyện bổ sung. Dung lượng bộ trích xuất dùng chung nằm trong Lưu trữ & Dữ liệu.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showRecorder) { PersonalVoiceRecorderView() }
        .onDisappear { manager.stopPlayback() }
        .alert("Đổi tên bản thu", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Tên giọng", text: $draftName)
            Button("Lưu") { if let profile = renaming { manager.rename(profile, name: draftName) }; renaming = nil }
            Button("Hủy", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Xóa bản thu và toàn bộ hồ sơ giọng?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Chuyển vào Thùng rác", role: .destructive) { if let profile = removing { manager.remove(profile) }; removing = nil }
        } message: { Text("Bản thu gốc và hồ sơ theo mô hình được chuyển vào Thùng rác. Giọng đang chọn trở về giọng dựng sẵn.") }
        .confirmationDialog("Gỡ hồ sơ VieNeu?", isPresented: Binding(get: { removingModel != nil }, set: { if !$0 { removingModel = nil } })) {
            Button("Gỡ hồ sơ", role: .destructive) { if let profile = removingModel { manager.removeModel(profile, model: .vieneu) }; removingModel = nil }
        } message: { Text("Giữ nguyên bản thu gốc. Bạn có thể tạo lại hồ sơ khi cần.") }
    }

    private func recordingCard(_ profile: PersonalVoiceProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: "waveform.circle.fill").font(.system(size: 30)).foregroundStyle(TransToolsTheme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(profile.name).font(.headline)
                    Text("\(Int(profile.duration)) giây · \(ByteCountFormatter.string(fromByteCount: manager.sizes[profile.id] ?? 0, countStyle: .file)) · \(profile.created.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Bản thu gốc").font(.caption.weight(.medium)).foregroundStyle(TransToolsTheme.accent)
            }
            if let text = profile.referenceText {
                Text(text).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack(spacing: 10) {
                Button { manager.previewOriginal(profile) } label: { Label("Nghe bản gốc", systemImage: "play.fill") }
                    .buttonStyle(TransToolsActionButtonStyle())
                Button("Dừng") { manager.stopPlayback() }.buttonStyle(TransToolsActionButtonStyle())
                Button("Đổi tên") { draftName = profile.name; renaming = profile }.buttonStyle(TransToolsActionButtonStyle())
                Spacer()
                Button("Thư mục") { NSWorkspace.shared.activateFileViewerSelecting([PersonalVoiceManager.root.appendingPathComponent(profile.id.uuidString)]) }
                    .buttonStyle(TransToolsActionButtonStyle())
                Button("Xóa bản thu", role: .destructive) { removing = profile }.buttonStyle(TransToolsActionButtonStyle())
            }.disabled(busy)
            Divider()
            ForEach(PersonalVoiceModel.allCases) { model in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(model.title).font(.subheadline.bold())
                        Spacer()
                        Text(manager.hasModel(profile, model: model) ? "Hồ sơ đã tạo" : "Chưa tạo hồ sơ")
                            .font(.caption).foregroundStyle(manager.hasModel(profile, model: model) ? TransToolsTheme.accent : .secondary)
                    }
                    HStack {
                        if manager.hasModel(profile, model: model) {
                            Button("Đọc thử câu mới") { Task { await manager.test(profile) } }
                                .buttonStyle(TransToolsActionButtonStyle()).disabled(busy || !model.isInstalled)
                            Button(UserDefaults.standard.string(forKey: "TTS_vieneu_Voice_vi") == profile.voiceID && LanguageVoicePreferences.selection(for: "vi") == .vieneu ? "Đang dùng" : "Dùng tiếng Việt") { manager.use(profile) }
                                .buttonStyle(TransToolsActionButtonStyle(prominent: true)).disabled(busy || !model.isInstalled)
                            Spacer()
                            Button("Gỡ hồ sơ", role: .destructive) { removingModel = profile }
                                .buttonStyle(TransToolsActionButtonStyle()).disabled(busy)
                        } else {
                            Button("Tạo hồ sơ giọng") { Task { await manager.createModel(profile, model: model) } }
                                .buttonStyle(TransToolsActionButtonStyle(prominent: true)).disabled(busy || !model.isInstalled)
                            if !model.isInstalled { Text("Cần cài mô hình").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }.padding(18).transToolsPanel()
    }
}
