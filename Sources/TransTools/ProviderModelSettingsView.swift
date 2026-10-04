import SwiftUI

/// Each provider loads its own catalog without changing the active translation engine.
struct ProviderModelSettingsView: View {
    @ObservedObject var model: MeetingModel
    let provider: AIProvider
    @State private var catalog: [String] = []
    @State private var selected = ""
    @State private var loading = false
    @State private var message = ""
    @State private var fetched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("Model").font(.callout.weight(.semibold))
                if catalog.isEmpty {
                    Text(selected.isEmpty ? "Chưa chọn model" : selected)
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Picker("Model", selection: Binding(get: { selected }, set: { value in
                        selected = value
                        model.updateModelName(value, for: provider)
                    })) {
                        if !catalog.contains(selected) {
                            Text(selected.isEmpty ? "Chọn model" : "\(selected) · chưa xác nhận").tag(selected)
                        }
                        ForEach(catalog, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().controlSize(.large).frame(maxWidth: .infinity)
                }
                Button { Task { await reload() } } label: {
                    Label(loading ? "Đang tải…" : "Tải model", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SettingsActionButtonStyle()).disabled(loading)
            }
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if fetched && !catalog.contains(selected) {
                Label("Model đã lưu không có trong danh sách mới. Hãy chọn model khả dụng.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("Danh sách lấy từ \(provider.shortName), chỉ gồm model hỗ trợ văn bản. Lựa chọn được lưu riêng cho nhà cung cấp này.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task {
            selected = UserDefaults.standard.string(forKey: "AIModel_\(provider.rawValue)") ?? provider.defaultModel
            await reload()
        }
        .onChange(of: model.modelName) { _, value in
            if model.provider == provider { selected = value }
        }
    }

    @MainActor private func reload() async {
        guard !loading else { return }
        let key = CredentialStore.read(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { message = "Lưu API key trước khi tải danh sách model."; return }
        loading = true; message = ""
        defer { loading = false }
        do {
            let list = try await AITranslator.fetchModels(for: provider, key: key)
            guard !Task.isCancelled, CredentialStore.read(for: provider).trimmingCharacters(in: .whitespacesAndNewlines) == key else { return }
            catalog = list; fetched = true
            if model.provider == provider { model.availableModels = list }
            if model.coPilotProvider == provider { model.availableCoPilotModels = list }
            message = "Đã tải \(list.count) model từ nhà cung cấp."
        } catch {
            if !Task.isCancelled { message = "Chưa tải được model: \(error.localizedDescription). Nhấn Tải model để thử lại." }
        }
    }
}
