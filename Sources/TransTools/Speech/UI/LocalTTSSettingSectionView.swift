import SwiftUI

public struct LocalTTSSettingSectionView: View {
    @ObservedObject private var modelManager = LocalTTSModelManager.shared
    @ObservedObject private var tts = TTSService.shared
    @State private var isCheckingUpdate = false
    @State private var updateCheckMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var showLicense = false

    private let defaultManifest = LocalTTSModelManifest.default

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Công cụ đọc văn bản")
                .font(.headline)

            VStack(spacing: 12) {
                // Engine Option 1: Giọng macOS
                naturalLocalVoiceCard
                systemVoiceCard
                onlineVoiceCard
            }

        }
    }

    // MARK: - Giọng macOS Card
    private var systemVoiceCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: (!modelManager.isNaturalVoiceEnabled && !tts.useEdgeNaturalVoice) ? "largecircle.fill.circle" : "circle")
                .foregroundStyle((!modelManager.isNaturalVoiceEnabled && !tts.useEdgeNaturalVoice) ? Color.accentColor : Color.secondary)
                .font(.system(size: 16))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Giọng cơ bản")
                    .font(.subheadline).bold()
                Text("Local • Nhanh • Không cần tải")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill((!modelManager.isNaturalVoiceEnabled && !tts.useEdgeNaturalVoice) ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke((!modelManager.isNaturalVoiceEnabled && !tts.useEdgeNaturalVoice) ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            modelManager.isNaturalVoiceEnabled = false
            TTSService.shared.useEdgeNaturalVoice = false
        }
    }

    // MARK: - Giọng tự nhiên trên máy Card
    private var onlineVoiceCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: !modelManager.isNaturalVoiceEnabled && tts.useEdgeNaturalVoice ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Giọng AI trực tuyến · Edge").font(.subheadline).bold()
                Text("Cần mạng • Nội dung đọc gửi tới dịch vụ giọng nói").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { modelManager.isNaturalVoiceEnabled = false; tts.useEdgeNaturalVoice = true }
    }

    private var naturalLocalVoiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: modelManager.isNaturalVoiceEnabled ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(modelManager.isNaturalVoiceEnabled ? Color.accentColor : Color.secondary)
                    .font(.system(size: 16))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Giọng tự nhiên")
                            .font(.subheadline).bold()

                        Text("Local")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(Color.green)
                            .clipShape(Capsule())
                    }

                    Text("Offline sau khi tải • Việt, Anh, Nhật, Hàn • Tiếng Trung dùng giọng cơ bản")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider().opacity(0.5)

            switch modelManager.state {
            case .notInstalled: notInstalledView
            case .downloading(let progress, let written, let total): downloadingView(progress: progress, written: written, total: total)
            case .verifying: verifyingView
            case .installed(let version, let usage): installedView(version: version, diskUsage: usage)
            case .failed(let error): failedView(error: error)
            }

        }
        .sheet(isPresented: $showLicense) {
            modelLicenseSheet
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(modelManager.isNaturalVoiceEnabled ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(modelManager.isNaturalVoiceEnabled ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var modelLicenseSheet: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "doc.text")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(TransToolsTheme.accent)
                    .frame(width: 54, height: 54)
                    .background(TransToolsTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 7) {
                    Text("ĐIỀU KHOẢN SỬ DỤNG")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(TransToolsTheme.accent)
                    Text("Giấy phép giọng tự nhiên")
                        .font(.system(size: 23, weight: .bold))
                    Text("Supertonic 3 · BigScience Open RAIL-M")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TransToolsTheme.accent.opacity(0.04))

            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Vui lòng đọc giấy phép trước khi tải mô hình. Giấy phép quy định các điều kiện sử dụng và phân phối.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Nội dung giấy phép gốc").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("English · 18/08/2022").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ScrollView {
                    Text(Self.modelLicense)
                        .font(.system(size: 12)).lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(18)
                }
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.10)))
            }
            .padding(24)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Chọn “Đồng ý & Tải giọng” nghĩa là bạn đồng ý tuân thủ giấy phép này.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Button("Để sau") { showLicense = false }
                        .buttonStyle(SpeechSettingsButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button {
                        showLicense = false
                        modelManager.downloadAndInstall(manifest: defaultManifest)
                    } label: {
                        Label("Đồng ý & Tải giọng", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(SettingsActionButtonStyle(prominent: true))
                    .disabled(Bundle.main.url(forResource: "Supertonic-Model-OpenRAIL", withExtension: "txt", subdirectory: "Licenses") == nil)
                }
            }
            .padding(24)
        }
        .frame(width: 680, height: 590)
    }

    private static var modelLicense: String {
        guard let url = Bundle.main.url(forResource: "Supertonic-Model-OpenRAIL", withExtension: "txt", subdirectory: "Licenses"),
              let text = try? String(contentsOf: url) else { return "Không tìm thấy giấy phép. Vui lòng cài lại app trước khi tải mô hình." }
        return text
    }

    // MARK: - State 1: Chưa cài đặt
    private var notInstalledView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Chưa cài đặt")
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Dung lượng tải: \(defaultManifest.formattedSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: {
                showLicense = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Tải & Bật")
                }
                .frame(minWidth: 150)
            }
            .buttonStyle(SpeechSettingsButtonStyle(prominent: true))
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - State 2: Downloading
    private func downloadingView(progress: Double, written: Int64, total: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Đang tải giọng tự nhiên")
                    .font(.caption).bold()
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit()).bold()
            }

            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)

            HStack {
                let writtenMB = ByteCountFormatter.string(fromByteCount: written, countStyle: .file)
                let totalMB = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                Text("\(writtenMB) / \(totalMB)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Hủy") {
                    modelManager.cancelDownload()
                }
                .buttonStyle(SpeechSettingsButtonStyle())
                .controlSize(.large)
            }
        }
    }

    // MARK: - State 3: Verifying
    private var verifyingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.large)
            Text("Đang kiểm tra tính toàn vẹn và cài đặt mô hình…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - State 4: Installed
    private func installedView(version: String, diskUsage: Int64) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Label("Đã cài", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("Dùng offline", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("Không cần mạng", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .font(.caption)

            HStack {
                Text("Dung lượng: \(modelManager.diskUsageFormatted) · Phiên bản: v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 8) {
                if !modelManager.isNaturalVoiceEnabled {
                    Button("Bật") {
                        modelManager.isNaturalVoiceEnabled = true
                    }
                    .buttonStyle(SpeechSettingsButtonStyle(prominent: true))
                    .controlSize(.large)
                }

                Button(action: {
                    Task {
                        isCheckingUpdate = true
                        updateCheckMessage = nil
                        let hasUpdate = await modelManager.checkForUpdate()
                        isCheckingUpdate = false
                        updateCheckMessage = hasUpdate ? "Đã có bản cập nhật mới!" : "Đã dùng phiên bản tương thích mới nhất trong TransTools."
                    }
                }) {
                    if isCheckingUpdate {
                        ProgressView().controlSize(.large)
                    } else {
                        Text("Kiểm tra cập nhật")
                    }
                }
                .buttonStyle(SpeechSettingsButtonStyle())
                .controlSize(.large)

                Button("Xóa mô hình", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .buttonStyle(SpeechSettingsButtonStyle())
                .controlSize(.large)
            }

            if let updateMsg = updateCheckMessage {
                Text(updateMsg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            "Xóa mô hình giọng tự nhiên?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Xóa mô hình", role: .destructive) {
                modelManager.removeModel()
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Mô hình sẽ bị xóa. TransTools sẽ chuyển về giọng cơ bản.")
        }
    }

    // MARK: - State 5: Failed
    private func failedView(error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Thử lại") {
                    showLicense = true
                }
                .buttonStyle(SpeechSettingsButtonStyle(prominent: true))
                .controlSize(.large)

                Button("Hủy") {
                    modelManager.cancelDownload()
                }
                .buttonStyle(SpeechSettingsButtonStyle())
                .controlSize(.large)
            }
        }
    }

}

struct SpeechSettingsButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(minHeight: 40)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1) : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(prominent ? 0 : 0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct SpeechPlaybackSettingsView: View {
    @ObservedObject private var player = TTSAudioPlayer.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Khi có câu mới").font(.headline)
            HStack(spacing: 12) {
                ForEach(TTSPlaybackPolicy.allCases) { policy in
                    Button { player.policy = policy } label: {
                        HStack(spacing: 10) {
                            Image(systemName: player.policy == policy ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(policy == .interruptCurrent ? "Ưu tiên câu mới" : "Đọc tuần tự").font(.system(size: 13, weight: .semibold))
                                Text(policy == .interruptCurrent ? "Ngắt câu đang đọc" : "Xếp hàng và đọc hết từng câu").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .background(player.policy == policy ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(player.policy == policy ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
