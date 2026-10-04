import SwiftUI
import AppKit

enum SettingsSection: Int, CaseIterable, Identifiable {
    case translation = 0
    case aiModels = 1
    case chipchip = 2
    case speech = 3
    case permissions = 4
    case system = 5
    case storage = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .translation: return "Dịch & Phụ đề"
        case .aiModels: return "AI & Kết nối"
        case .chipchip: return "Chip Chip & Sức khỏe"
        case .speech: return "Giọng đọc & Phát âm"
        case .permissions: return "Quyền & Phím tắt"
        case .storage: return "Lưu trữ & Dữ liệu"
        case .system: return "Hệ thống & Cập nhật"
        }
    }

    var subtitle: String {
        switch self {
        case .translation: return "Chuyên ngành, ngôn ngữ mặc định & công cụ dịch"
        case .aiModels: return "Cấu hình Google Gemini, OpenAI, Claude, DeepSeek"
        case .chipchip: return "Hoạt cảnh, đi dạo Dock & nhắc nhở giải lao Pomodoro"
        case .speech: return "Giọng tự nhiên Local, giọng AI trực tuyến & phát âm"
        case .permissions: return "Trạng thái cấp quyền & danh sách phím tắt"
        case .storage: return "Mô hình đã cài, học liệu offline & cache"
        case .system: return "Tự khởi động cùng Mac & kiểm tra phiên bản mới"
        }
    }

    var icon: String {
        switch self {
        case .translation: return "captions.bubble.fill"
        case .aiModels: return "sparkles"
        case .chipchip: return "face.smiling.fill"
        case .speech: return "waveform"
        case .permissions: return "hand.raised.fill"
        case .storage: return "internaldrive.fill"
        case .system: return "gearshape.2.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .translation: return .blue
        case .aiModels: return .purple
        case .chipchip: return .orange
        case .speech: return .teal
        case .permissions: return .green
        case .storage: return .teal
        case .system: return .indigo
        }
    }
}

// MARK: - Main Settings Dashboard View (Full Page Workspace)

struct SettingsDashboardView: View {
    @ObservedObject var model: MeetingModel
    @State private var activeSection: SettingsSection = .translation
    @State private var editingKeyForProvider: AIProvider? = nil
    @State private var tempKeyInput: String = ""
    @State private var keyRevision = 0

    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar Navigation (macOS System Settings Style)
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TransToolsTheme.navy)
                    Text("Cài đặt")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 10)

                // Navigation Items
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(SettingsSection.allCases) { section in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    activeSection = section
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(section.iconColor.opacity(activeSection == section ? 1.0 : 0.15))
                                            .frame(width: 26, height: 26)

                                        Image(systemName: section.icon)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(activeSection == section ? .white : section.iconColor)
                                    }

                                    Text(section.title)
                                        .font(.system(size: 13, weight: activeSection == section ? .semibold : .medium))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .foregroundStyle(activeSection == section ? (Color.primary) : .secondary)

                                    Spacer()

                                    if activeSection == section {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(TransToolsTheme.navy)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(activeSection == section ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.18) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain).textSelection(.disabled).transToolsButtonCursor()
                            .accessibilityAddTraits(activeSection == section ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 10)
                }

                Spacer()

                // Sidebar Footer Version Info
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Trans Tools \(appVersionDisplay)")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(width: 280)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))

            Divider()

            // Right Content Area (Spacious & Clean Layout)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    // Section Title Header
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: activeSection.icon)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(activeSection.iconColor)
                            Text(activeSection.title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.primary)
                        }

                        Text(activeSection.subtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)

                    // Content Switcher
                    switch activeSection {
                    case .translation:
                        translationSettingsSection
                    case .aiModels:
                        aiModelsSettingsSection
                    case .chipchip:
                        chipchipSettingsSection
                    case .speech:
                        speechSettingsSection
                    case .permissions:
                        permissionsSettingsSection
                    case .storage:
                        StorageSettingsView(model: model)
                    case .system:
                        systemSettingsSection
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        }
        .onAppear {
            if model.selectedSettingsSection > 0, let target = SettingsSection(rawValue: model.selectedSettingsSection) {
                activeSection = target
                model.selectedSettingsSection = 0
            }
            model.checkAllPermissions()
        }
        .onChange(of: model.selectedSettingsSection) { newSec in
            if newSec > 0, let target = SettingsSection(rawValue: newSec) {
                activeSection = target
                model.selectedSettingsSection = 0
            }
        }
    }

    // MARK: - Section 1: Translation & Subtitles
    private var translationSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Card: Domain Specialty
            settingsCard(title: "Chuyên ngành & Ngữ cảnh", icon: "briefcase.fill", color: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Chọn chuyên ngành để AI hiểu thuật ngữ và cách diễn đạt phù hợp với công việc của bạn.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Picker("Chuyên ngành", selection: $model.domainSpecialty) {
                        ForEach(DomainSpecialty.allCases) { domain in
                            Label(domain.title, systemImage: domain.icon).tag(domain)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .controlSize(.large)

                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 11))
                        Text(model.domainSpecialty == .developer ? "Ví dụ Developer: Giữ nguyên PR, commit, deploy, refactor, bug, staging..." : "Ví dụ Business: Dùng phong cách trang trọng, lịch sự phù hợp với đối tác & cuộc họp kinh doanh.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            settingsCard(title: "Nhịp dịch cuộc họp", icon: "captions.bubble", color: .teal) {
                Picker("Độ trễ bản dịch", selection: $model.liveTranslationPacing) {
                    ForEach(LiveTranslationPacing.allCases) { mode in Text(mode.title).tag(mode) }
                }.pickerStyle(.segmented).controlSize(.large)
                Text("Tiếng gốc hiện ngay. Bản dịch chờ khoảng ngắt: Nhanh 0,3 giây · Cân bằng 0,8 giây · Đủ ngữ cảnh 1,2 giây. Khi nói liên tục, thời gian chờ tối đa tương ứng 1 / 2 / 3 giây; chưa gồm thời gian xử lý dịch.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            // Card: Translation Engines
            settingsCard(title: "Bộ máy dịch thuật chính", icon: "network", color: .indigo) {
                VStack(alignment: .leading, spacing: 10) {
                    // Apple Native
                    engineRow(
                        title: "Translate · Local",
                        subtitle: "Dịch Local. Dùng ngoại tuyến sau khi tải ngôn ngữ được hỗ trợ.",
                        icon: "apple.logo",
                        isSelected: model.provider == .apple
                    ) {
                        model.setProvider(.apple)
                    }

                    // Free Google Translate
                    engineRow(
                        title: "Google Dịch (Miễn phí)",
                        subtitle: "Nhanh chóng, ổn định, hỗ trợ dịch tự động đa ngôn ngữ.",
                        icon: "bolt.fill",
                        isSelected: model.provider == .free
                    ) {
                        model.setProvider(.free)
                    }

                    // Cloud AI Models
                    engineRow(
                        title: "Cloud AI (Google Gemini, OpenAI, Claude, DeepSeek)",
                        subtitle: "Chất lượng dịch tự nhiên nhất, phân tích ngữ cảnh dài và gợi ý câu trả lời thông minh.",
                        icon: "sparkles",
                        isSelected: model.provider != .apple && model.provider != .free
                    ) {
                        if let firstAI = [AIProvider.gemini, .openai, .deepseek, .claude].first(where: { model.hasKeyForProvider($0) }) {
                            model.setProvider(firstAI)
                        } else {
                            activeSection = .aiModels
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section 2: AI Models & Keys
    private var aiModelsSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Cấu hình API Key từ các nhà cung cấp AI để mở khóa chất lượng dịch thuật cao cấp nhất, phân tích ngữ cảnh cuộc họp và gợi ý câu phản xạ giao tiếp:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Label("API key được mã hóa AES-GCM bằng CryptoKit và lưu trên máy.", systemImage: "lock.shield")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if let error = CredentialStore.lastError {
                Text(error).font(.system(size: 12)).foregroundStyle(.orange)
            }

            ForEach([AIProvider.gemini, .openai, .deepseek, .claude]) { p in
                let hasKey = model.hasKeyForProvider(p)
                let isSelected = (model.provider == p)

                settingsCard(title: p.displayName, icon: p.icon, color: isSelected ? TransToolsTheme.navy : .secondary) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(p.displayName)
                                        .font(.system(size: 13, weight: .bold))

                                    if hasKey {
                                        Text("✓ Đã lưu Key")
                                            .font(.system(size: 9.5, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.15))
                                            .foregroundStyle(.green)
                                            .clipShape(Capsule())
                                    } else {
                                        Text("Chưa cài Key")
                                            .font(.system(size: 9.5, weight: .medium))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.12))
                                            .foregroundStyle(.secondary)
                                            .clipShape(Capsule())
                                    }
                                }

                                if hasKey {
                                    ProviderModelSettingsView(model: model, provider: p)
                                        .id("\(p.rawValue)-\(keyRevision)")
                                } else {
                                    Text("Nhập API key để tải và chọn model từ nhà cung cấp.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }

                            HStack(spacing: 12) {
                            if hasKey {
                                Button(isSelected ? "Đang chọn" : "Kích hoạt dùng AI này") {
                                    model.setProvider(p)
                                }
                                .buttonStyle(SettingsActionButtonStyle(prominent: true))
                                .tint(isSelected ? .green : TransToolsTheme.navy)
                                .controlSize(.regular)
                            }

                            Button(editingKeyForProvider == p ? "Đóng form" : (hasKey ? "Đổi Key" : "Nhập Key")) {
                                tempKeyInput = hasKey ? CredentialStore.read(for: p) : ""
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    editingKeyForProvider = (editingKeyForProvider == p ? nil : p)
                                }
                            }
                            .buttonStyle(SettingsActionButtonStyle())
                            .controlSize(.regular)
                            }
                        }

                        // Inline Key Editing Form
                        if editingKeyForProvider == p {
                            VStack(alignment: .leading, spacing: 8) {
                                Divider()

                                HStack {
                                    Text("Nhập mã API Key:")
                                        .font(.system(size: 11, weight: .semibold))
                                    Spacer()
                                    if let url = URL(string: p.apiKeyURL), !p.apiKeyURL.isEmpty {
                                        Link("Lấy API Key trên trang \(p.shortName) ↗", destination: url)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(TransToolsTheme.navy)
                                    }
                                }

                                HStack(spacing: 8) {
                                    SecureField("Dán API Key bí mật vào đây...", text: $tempKeyInput)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11.5, design: .monospaced))

                                    Button("Lưu & Áp dụng") {
                                        model.saveKeyForProvider(tempKeyInput, for: p)
                                        keyRevision += 1
                                        model.setProvider(p)
                                        withAnimation { editingKeyForProvider = nil }
                                    }
                                    .buttonStyle(SettingsActionButtonStyle(prominent: true))
                                    .tint(TransToolsTheme.navy)
                                    .controlSize(.regular)
                                    .disabled(tempKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    if hasKey {
                                        Button("Xóa Key") {
                                            model.saveKeyForProvider("", for: p)
                                            keyRevision += 1
                                            withAnimation { editingKeyForProvider = nil }
                                        }
                                        .buttonStyle(SettingsActionButtonStyle())
                                        .controlSize(.regular)
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section 3: Chip Chip & Ergonomics
    private var chipchipSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "Trợ lý ảo Chip Chip", icon: "sparkles.tv.fill", color: .orange) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: Binding(
                        get: { model.isFloatingMascotVisible },
                        set: { _ in model.toggleFloatingMascot() }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bật Trợ lý Chip Chip nổi trên màn hình")
                                .font(.system(size: 13, weight: .medium))
                            Text("Chip Chip sẽ đồng hành trên desktop, hiển thị bản dịch khi bôi đen Option + D và nhắc nhở cuộc họp.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(TrailingSettingsToggleStyle())

                    Divider()

                    Toggle(isOn: $model.isDockWalkEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Đi dạo dọc Dock Bar khi rảnh rỗi")
                                .font(.system(size: 13, weight: .medium))
                            Text("Khi máy tính nghỉ và không họp, Chip Chip sẽ tự do dạo bước thư giãn phía trên thanh Dock.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(TrailingSettingsToggleStyle())

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tạo hình nhân vật")
                            .font(.system(size: 12.5, weight: .medium))
                        HStack(spacing: 12) {
                            mascotStyleButton("Minh họa hoạt hình", icon: "photo", value: "sprite")
                            mascotStyleButton("Pixel Art", icon: "square.grid.3x3", value: "pixel")
                        }
                    }

                }
            }

            // Health & Pomodoro Reminder
            settingsCard(title: "Trợ lý sức khỏe công thái học (Pomodoro Ergonomics)", icon: "cup.and.saucer.fill", color: .teal) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Nhắc nhở thông minh giúp bảo vệ mắt và cột sống trong những buổi họp dài hoặc phiên làm việc tập trung:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Text("Chu kỳ nhắc giải lao:")
                            .font(.system(size: 12.5, weight: .medium))
                            .fixedSize()

                        Picker("", selection: $model.healthReminderMinutes) {
                            Text("Mỗi 30 phút").tag(30)
                            Text("Mỗi 45 phút (Khuyên dùng)").tag(45)
                            Text("Mỗi 60 phút").tag(60)
                            Text("Tắt tính năng này").tag(0)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.large)
                        .frame(width: 260)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(.teal)
                        Text("Khi tới giờ, Chip Chip sẽ nhẹ nhàng chuyển sang hoạt cảnh uống trà và hiển thị lời nhắc: chớp mắt, uống nước ấm và thả lỏng vai.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.teal.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Section 4: Speech & TTS Settings
    private var speechSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "Cấu hình giọng đọc & Phát âm", icon: "waveform", color: .teal) {
                SpeechSettingsView()
            }
        }
    }

    // MARK: - Section 5: Permissions & Global Hotkeys
    private var permissionsSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Permissions
            settingsCard(title: "Quyền bảo mật hệ thống", icon: "shield.lefthalf.filled", color: .green) {
                VStack(spacing: 10) {
                    permissionRow(
                        title: "Ghi màn hình & Âm thanh hệ thống",
                        subtitle: "Bắt âm thanh từ Zoom, Teams, Google Meet, YouTube",
                        icon: "display",
                        isGranted: model.hasScreenCapturePermission,
                        onRequest: { model.requestScreenCapturePermission() }
                    )

                    permissionRow(
                        title: "Microphone",
                        subtitle: "Thu âm giọng nói của bạn để phiên dịch song ngữ",
                        icon: "mic.fill",
                        isGranted: model.hasMicrophonePermission,
                        onRequest: { model.requestMicrophonePermission() }
                    )

                    permissionRow(
                        title: "Nhận diện giọng nói (Speech Recognition)",
                        subtitle: "Chuyển đổi âm thanh cuộc họp thành văn bản phụ đề",
                        icon: "waveform.and.mic",
                        isGranted: model.hasSpeechRecognitionPermission,
                        onRequest: { model.requestSpeechRecognitionPermission() }
                    )

                    permissionRow(
                        title: "Trợ năng (Accessibility)",
                        subtitle: "Kích hoạt các phím tắt dịch bôi đen và sửa ngữ pháp",
                        icon: "hand.raised.fill",
                        isGranted: model.hasAccessibilityPermission,
                        onRequest: { model.requestAccessibilityPermission() }
                    )
                }
            }

            // Hotkeys Guide
            settingsCard(title: "Bảng phím tắt toàn cục (Sử dụng ở bất kỳ đâu)", icon: "command", color: .blue) {
                VStack(spacing: 8) {
                    hotkeyItem(key: "Option + D", desc: "Bôi đen từ/câu bất kỳ để dịch tức thì trên bong bóng Chip Chip")
                    hotkeyItem(key: "Option + S", desc: "Chụp ảnh chọn vùng màn hình và nhận diện văn bản OCR để dịch")
                    hotkeyItem(key: "Option + E", desc: "Dịch nhanh tiếng Việt sang tiếng Anh theo ngữ cảnh chuyên ngành")
                    hotkeyItem(key: "Option + F", desc: "Kiểm tra lỗi ngữ pháp và làm mượt câu văn tiếng Anh")
                }
            }
        }
    }

    // MARK: - Section 6: System & Updates
    private var systemSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "Phiên bản & Cập nhật", icon: "arrow.triangle.2.circlepath", color: .teal) {
                SettingsUpdateTabView()
            }

            settingsCard(title: "Khởi động & Trải nghiệm", icon: "power", color: .indigo) {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Tự động mở Trans Tools khi khởi động máy Mac")
                            .font(.system(size: 13, weight: .medium))
                        Text("Giúp phím tắt dịch nhanh và Trợ lý Chip Chip luôn sẵn sàng phục vụ bạn.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("Tự động mở Trans Tools khi khởi động máy Mac", isOn: Binding(
                        get: { model.isLaunchAtLoginEnabled },
                        set: { model.setLaunchAtLogin(enabled: $0) }
                    ))
                    .toggleStyle(.switch).labelsHidden().controlSize(.regular)
                    .fixedSize()
                }

            }
        }
    }

    private func mascotStyleButton(_ title: String, icon: String, value: String) -> some View {
        Button { model.mascotStyle = value } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(title).lineLimit(1)
                Spacer(minLength: 8)
                if model.mascotStyle == value { Image(systemName: "checkmark.circle.fill") }
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(model.mascotStyle == value ? TransToolsTheme.accent : Color.primary)
            .background(model.mascotStyle == value ? TransToolsTheme.accent.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.mascotStyle == value ? TransToolsTheme.accent.opacity(0.45) : Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain).textSelection(.disabled).transToolsButtonCursor()
        .accessibilityAddTraits(model.mascotStyle == value ? .isSelected : [])
    }

    // MARK: - Helper Views & Components

    private func settingsCard<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Divider()

            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transToolsPanel()
    }

    private func engineRow(title: String, subtitle: String, icon: String, isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? TransToolsTheme.navy : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.8))
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? TransToolsTheme.navy : Color.secondary.opacity(0.3))
            }
            .padding(10)
            .background(isSelected ? TransToolsTheme.navy.opacity(0.08) : Color.primary.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain).textSelection(.disabled).transToolsButtonCursor()
    }

    private func permissionRow(title: String, subtitle: String, icon: String, isGranted: Bool, onRequest: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isGranted ? .green : .orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Text("✓ Đã cấp quyền")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            } else {
                Button("Cấp quyền") { onRequest() }
                    .buttonStyle(SettingsActionButtonStyle(prominent: true))
                    .tint(TransToolsTheme.navy)
                    .controlSize(.regular)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func hotkeyItem(key: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(TransToolsTheme.navy.opacity(0.12))
                .foregroundStyle(TransToolsTheme.navy)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(desc)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

typealias SettingsActionButtonStyle = TransToolsActionButtonStyle

/// A full-width settings row with a consistently aligned trailing switch.
struct TrailingSettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 20) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
