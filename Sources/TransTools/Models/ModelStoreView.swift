import SwiftUI

struct ModelStoreView: View {
    @ObservedObject private var manager = ModelManager.shared
    @ObservedObject private var external = ExternalTTSModelManager.shared
    @State private var licenseAction: String?
    @State private var page = "models"
    @State private var filter = "recommended"
    @State private var pendingRemoval: ModelInventoryItem?
    @State private var text = "Hôm nay chúng ta sẽ thử giọng đọc tiếng Việt."
    @State private var language = "vi"
    private var visible: [ModelInventoryItem] {
        manager.items.filter { item in
            if filter == "installed" { return item.state == .installed || item.state == .ready }
            if filter == "recommended" { return item.descriptor.recommended }
            return item.descriptor.category.rawValue == filter
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModelStoreTabs(selection: $page, options: [("models", "Mô hình"), ("voices", "Giọng của tôi")])
            if page == "voices" { PersonalVoiceSettingsView() } else { catalog }
        }
    }
    private var catalog: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Mô hình trên thiết bị", systemImage: "cpu").font(.headline)
                Spacer()
                Button { Task { await manager.updateCatalog() } } label: {
                    Label(manager.updatingCatalog ? "Đang cập nhật…" : "Cập nhật danh mục", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(TransToolsActionButtonStyle())
                .disabled(manager.updatingCatalog || manager.inUse || manager.installing)
                Button("Làm mới dung lượng") { Task { await manager.refresh() } }.buttonStyle(TransToolsActionButtonStyle())
            }
            Text("Cài dữ liệu cần thiết, chọn giọng theo ngôn ngữ và quản lý dung lượng. Bộ xử lý native dùng chung trong ứng dụng.")
                .font(.subheadline).foregroundStyle(.secondary)
            if let packs = manager.registry?.packs {
                ForEach(packs) { pack in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pack.name).font(.subheadline.bold())
                            Text(pack.modelIDs.compactMap { manager.registry?.model($0)?.name }.joined(separator: " · ") + " · chỉ tải thành phần còn thiếu").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if manager.installingPack {
                            Button("Dừng cài gói") { manager.cancelPack() }.buttonStyle(TransToolsActionButtonStyle())
                        } else {
                            Button(packInstalled(pack) ? "Đã cài" : "Cài gói") { requestInstall("pack:" + pack.id) }.buttonStyle(TransToolsActionButtonStyle()).disabled(packInstalled(pack) || manager.inUse || manager.installing)
                        }
                    }.padding(14).transToolsPanel()
                }
            }
            ModelStoreTabs(selection: $filter, options: [("recommended", "Đề xuất"), ("tts", "TTS"), ("stt", "STT"), ("translation", "Dịch"), ("languageModel", "Ngôn ngữ"), ("installed", "Đã cài")])
            if visible.isEmpty { Text("Chưa có mô hình đã tích hợp trong nhóm này.").foregroundStyle(.secondary).padding(18) }
            ForEach(visible) { item in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.descriptor.name).font(.headline)
                            Text(item.descriptor.summary).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.state.title).font(.caption.bold()).foregroundStyle(TransToolsTheme.accent)
                    }
                    Text(item.descriptor.languages.joined(separator: " · ").uppercased() + " · Offline · " + item.descriptor.runtime.name)
                        .font(.caption).foregroundStyle(TransToolsTheme.accent)
                    HStack {
                        Text("Tải \(size(item.descriptor.downloadBytes))")
                        Text("Đã lưu \(size(item.installedBytes))")
                    }.font(.caption).foregroundStyle(.secondary)
                    if case let .downloading(fraction) = item.state { ProgressView(value: fraction) }
                    if item.state == .installing { Text(external.status).font(.caption).foregroundStyle(.secondary) }
                    if case let .failed(reason) = item.state { Text(reason).font(.caption).foregroundStyle(.red) }
                    if case let .incompatible(reason) = item.state { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        if item.state == .installed || item.state == .ready {
                            Button("Dùng cho \(language.uppercased())") { manager.setDefault(item.id, language: language) }
                                .buttonStyle(TransToolsActionButtonStyle(prominent: true)).disabled(manager.inUse || !item.descriptor.languages.contains(language))
                            Spacer()
                            Button("Gỡ mô hình", role: .destructive) { pendingRemoval = item }
                                .buttonStyle(TransToolsActionButtonStyle()).disabled(manager.inUse || manager.installing)
                        } else if item.state == .installing || isDownloading(item.state) {
                            Button("Tạm dừng") { manager.pause(item.id) }.buttonStyle(TransToolsActionButtonStyle())
                        } else if item.state == .paused {
                            Button("Tiếp tục tải") { manager.install(item.id) }.buttonStyle(TransToolsActionButtonStyle(prominent: true)).disabled(manager.inUse || manager.installing)
                            Button("Hủy") { manager.cancel(item.id) }.buttonStyle(TransToolsActionButtonStyle())
                        } else {
                            Button("Cài mô hình") { requestInstall(item.id) }.buttonStyle(TransToolsActionButtonStyle(prominent: true))
                                .disabled(manager.inUse || manager.installing || isIncompatible(item.state))
                        }
                    }
                    DisclosureGroup {
                        Text("Engine: \(item.descriptor.engineID) · Phiên bản: \(item.descriptor.version)\nGiấy phép: \(item.descriptor.license)\n\(item.descriptor.capabilities.voiceCloning ? "Hỗ trợ hồ sơ giọng mẫu" : "Dùng giọng dựng sẵn")\n\(manager.hardware.appleSilicon ? "Apple Silicon" : "Intel") · CPU \(manager.hardware.logicalCPUs) luồng · RAM \(size(Int64(manager.hardware.ramBytes)))")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text("Chi tiết").frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle()).transToolsButtonCursor()
                    }
                }.padding(18).transToolsPanel()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("So sánh giọng đọc").font(.headline)
                Picker("Ngôn ngữ", selection: $language) {
                    Text("Tiếng Việt").tag("vi"); Text("Tiếng Anh").tag("en"); Text("Tiếng Nhật").tag("ja"); Text("Tiếng Hàn").tag("ko")
                }
                TextEditor(text: $text).frame(height: 70).padding(6).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TransToolsTheme.accent.opacity(0.3)))
                HStack {
                    ForEach(manager.items.filter { $0.state == .installed && $0.descriptor.languages.contains(language) }) { item in
                        Button("Nghe \(item.descriptor.name)") { Task { await manager.test(item.id, text: text, language: language) } }
                            .buttonStyle(TransToolsActionButtonStyle()).disabled(manager.inUse || manager.installing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 600)
                    }
                    Button("Dừng") { manager.stopTesting() }.buttonStyle(TransToolsActionButtonStyle())
                }
                Text("Đo thời gian tạo audio và RTF thực tế; thử lần lượt để tránh nạp nhiều mô hình cùng lúc. Tối đa 600 ký tự.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(18).transToolsPanel()
            if !manager.message.isEmpty { Text(manager.message).font(.callout).foregroundStyle(.secondary) }
        }.sheet(isPresented: Binding(get: { licenseAction != nil }, set: { if !$0 { licenseAction = nil } })) {
            ModelLicenseView {
                guard let action = licenseAction else { return }
                licenseAction = nil
                performInstall(action)
            } cancel: { licenseAction = nil }
        }.task { await manager.refresh() }
        .onDisappear { manager.stopTesting() }
        .confirmationDialog("Gỡ \(pendingRemoval?.descriptor.name ?? "mô hình")?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Chuyển vào Thùng rác", role: .destructive) { if let id = pendingRemoval?.id { Task { await manager.remove(id) } }; pendingRemoval = nil }
        } message: { Text("Giữ bản thu cá nhân. Ngôn ngữ đang chọn mô hình này trở về giọng cơ bản.") }
    }
    private func packInstalled(_ pack: LanguagePack) -> Bool {
        pack.modelIDs.allSatisfy { id in manager.items.contains { $0.id == id && $0.state == .installed } }
    }
    private func requestInstall(_ action: String) {
        if action == "supertonic-3" || (action.hasPrefix("pack:") && !LocalTTSModelManager.shared.isInstalled) { licenseAction = action }
        else { performInstall(action) }
    }
    private func performInstall(_ action: String) {
        if action.hasPrefix("pack:") { manager.installPack(String(action.dropFirst(5))) } else { manager.install(action) }
    }
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    private func isDownloading(_ state: AIModelInstallationState) -> Bool { if case .downloading = state { return true }; return false }
    private func isIncompatible(_ state: AIModelInstallationState) -> Bool { if case .incompatible = state { return true }; return false }
}

private struct ModelLicenseView: View {
    let accept: () -> Void
    let cancel: () -> Void
    private var license: String? {
        guard let url = Bundle.main.url(forResource: "Supertonic-Model-OpenRAIL", withExtension: "txt", subdirectory: "Licenses") else { return nil }
        return try? String(contentsOf: url)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Giấy phép Supertonic 3", systemImage: "doc.text").font(.title2.bold())
            Text("Mô hình dùng Open RAIL-M. Đọc điều kiện sử dụng trước khi tải.").foregroundStyle(.secondary)
            ScrollView { Text(license ?? "Không tìm thấy giấy phép. Cần cài lại app trước khi tải.").font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .padding(16).transToolsPanel()
            HStack {
                Button("Để sau", action: cancel).buttonStyle(TransToolsActionButtonStyle())
                Spacer()
                Button("Đồng ý & Tải", action: accept).buttonStyle(TransToolsActionButtonStyle(prominent: true)).disabled(license == nil)
            }
        }.padding(24).frame(width: 640, height: 550)
    }
}

private struct ModelStoreTabs: View {
    @Binding var selection: String
    let options: [(String, String)]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { option in
                Button { selection = option.0 } label: {
                    Text(option.1).font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .foregroundStyle(selection == option.0 ? Color.white : TransToolsTheme.accent)
                        .background(selection == option.0 ? TransToolsTheme.accent : Color.white)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TransToolsTheme.accent.opacity(0.3), lineWidth: 1))
    }
}
