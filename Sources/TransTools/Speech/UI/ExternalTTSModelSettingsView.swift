import SwiftUI
import AppKit

struct ExternalTTSModelSettingsView: View {
    @ObservedObject private var manager = ExternalTTSModelManager.shared
    @ObservedObject private var router = TTSEngineRouter.shared
    @ObservedObject private var tts = TTSService.shared
    @State private var remove: ExternalTTSModel?
    @State private var removing = false
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mô hình theo ngôn ngữ").font(.headline)
            Text("Supertonic là công cụ mặc định. Chỉ tải mô hình bổ sung khi cần; VieNeu dùng bộ xử lý native có sẵn, Qwen cần bộ xử lý riêng. Chỉ một mô hình được nạp khi đọc.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(ExternalTTSModel.allCases) { model in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.title).font(.subheadline.bold())
                            Text(model.detail).font(.caption).foregroundStyle(.secondary)
                            Text(model.isInstalled ? "Đã cài · audio đã qua kiểm thử" : (model == .vieneu ? "Chưa cài · chỉ tải dữ liệu mô hình" : "Chưa cài · tải dữ liệu và bộ xử lý khi cần"))
                                .font(.caption).foregroundStyle(model.isInstalled ? TransToolsTheme.accent : .secondary)
                        }
                        Spacer()
                        Image(systemName: model.isInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                            .foregroundStyle(TransToolsTheme.accent).font(.title3)
                    }
                    HStack(spacing: 12) {
                        if manager.installing == model {
                            ProgressView().controlSize(.small)
                            Text("Đang tải & kiểm thử…").font(.caption)
                            Spacer()
                            Button("Hủy", action: manager.cancel).buttonStyle(TransToolsActionButtonStyle())
                        } else if model.isInstalled {
                            Button("Dùng cho " + (model == .vieneu ? "Tiếng Việt" : "Tiếng Trung")) {
                                tts.stop()
                                LanguageVoicePreferences.set(model == .vieneu ? .vieneu : .qwen, for: model.recommendedLanguage)
                                manager.refresh()
                            }.buttonStyle(TransToolsActionButtonStyle(prominent: true))
                            Button("Gỡ mô hình", role: .destructive) { remove = model }
                                .buttonStyle(TransToolsActionButtonStyle())
                        } else {
                            Button("Tải & Cài") { manager.install(model) }
                                .buttonStyle(TransToolsActionButtonStyle(prominent: true))
                                .disabled(!model.availableOnDevice)
                            if !model.availableOnDevice { Text("Qwen MLX cần chip Apple Silicon").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.disabled(tts.isSpeaking || router.isProcessing || removing || (manager.installing != nil && manager.installing != model))
                }.padding(16).transToolsPanel()
            }
            if !manager.status.isEmpty { Text(manager.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 16) {
                Link("Nguồn VieNeu", destination: URL(string: "https://github.com/pnnbao97/VieNeu-TTS")!)
                Link("Nguồn Qwen", destination: URL(string: "https://github.com/QwenLM/Qwen3-TTS")!)
                Link("Bộ xử lý MLX Audio", destination: URL(string: "https://github.com/Blaizzy/mlx-audio")!)
            }.font(.caption)
            Text("Mã nguồn và mô hình VieNeu/Qwen dùng Apache 2.0; thông tin nguồn và giấy phép được giữ cùng mô hình. Quản lý dung lượng, SDK và nhật ký tải trong Lưu trữ & Dữ liệu.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("Gỡ \(remove?.title ?? "mô hình")?", isPresented: Binding(get: { remove != nil }, set: { if !$0 { remove = nil } }), titleVisibility: .visible) {
            Button("Chuyển vào Thùng rác", role: .destructive) {
                guard let model = remove else { return }; remove = nil; removing = true
                Task {
                    await ExternalTTSSession.shared.releaseAndWait()
                    NSWorkspace.shared.recycle([model.directory]) { _, error in
                        Task { @MainActor in
                            removing = false; message = error.map { $0.localizedDescription } ?? (model == .vieneu ? "Đã gỡ dữ liệu VieNeu. Bộ xử lý có sẵn trong ứng dụng." : "Đã gỡ mô hình. Bộ xử lý Qwen được giữ để tải lại nhanh hơn.")
                            manager.refresh()
                        }
                    }
                }
            }
            Button("Hủy", role: .cancel) { remove = nil }
        } message: { Text("Dừng mô hình trước khi gỡ. Lựa chọn của bạn được giữ; khi thiếu mô hình sẽ dùng giọng dự phòng.") }
    }
}
