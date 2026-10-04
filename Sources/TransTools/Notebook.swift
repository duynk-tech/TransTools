import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Web-Style Tab Item (Flat Icons, Underline Indicator)

private struct NotebookWebTabItem: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? TransToolsTheme.accent : (isHovered ? .primary : .secondary))

                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? .primary : (isHovered ? .primary : .secondary))

                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            isSelected
                                ? TransToolsTheme.accent.opacity(0.14)
                                : Color.secondary.opacity(0.1)
                        )
                        .foregroundStyle(isSelected ? TransToolsTheme.accent : .secondary)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())

                // Web-style active indicator bar
                ZStack {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 2.5)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(TransToolsTheme.accent)
                            .frame(height: 2.5)
                    }
                }
            }
            .background(
                isHovered && !isSelected
                    ? Color.primary.opacity(0.04)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Meeting Notebook & Session Manager

struct MeetingNotebookView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var vocabManager = VocabularyManager.shared
    @State private var searchText = ""
    @State private var transcriptSearch = ""
    @State private var sessionToDelete: MeetingSession? = nil
    @State private var isEditingNotes = false

    var filteredSessions: [MeetingSession] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return model.sessions
        }
        let q = searchText.lowercased()
        return model.sessions.filter { session in
            session.title.lowercased().contains(q) ||
            session.audioSource.lowercased().contains(q) ||
            session.notes.lowercased().contains(q) ||
            session.captions.contains { $0.original.lowercased().contains(q) || $0.vietnamese.lowercased().contains(q) }
        }
    }

    var selectedSession: MeetingSession? {
        guard let id = model.selectedSessionID else { return filteredSessions.first }
        return model.sessions.first(where: { $0.id == id }) ?? filteredSessions.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Section Web-Style Tab Bar: Sổ tay cuộc họp vs Sổ từ vựng
            HStack(spacing: 4) {
                NotebookWebTabItem(
                    title: "Sổ tay cuộc họp",
                    icon: "bubble.left.and.text.bubble.right.fill",
                    count: model.sessions.count,
                    isSelected: model.selectedNotebookTab == 0
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        model.selectedNotebookTab = 0
                    }
                }

                NotebookWebTabItem(
                    title: "Sổ từ vựng",
                    icon: "character.book.closed.fill",
                    count: vocabManager.items.count,
                    isSelected: model.selectedNotebookTab == 1
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        model.selectedNotebookTab = 1
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
            .overlay(
                Divider().opacity(0.4),
                alignment: .bottom
            )

            if model.selectedNotebookTab == 0 {
                HSplitView {
            // Left Pane: Session List & Search
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("Tìm theo tiêu đề, nội dung...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider().opacity(0.5)

                // Sessions List
                if model.sessions.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "note.text")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary.opacity(0.4))

                        Text("Chưa có ghi chép")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text("Khi bạn bắt đầu và kết thúc một phiên họp, toàn bộ nội dung song ngữ và ghi chú sẽ tự động được lưu vào đây.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredSessions.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("Không tìm thấy cuộc họp nào")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filteredSessions) { session in
                                SessionRowItem(
                                    session: session,
                                    isSelected: selectedSession?.id == session.id,
                                    onSelect: {
                                        model.selectedSessionID = session.id
                                    },
                                    onDelete: {
                                        sessionToDelete = session
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 290, maxWidth: 350)
            .background(Color(nsColor: .windowBackgroundColor))

            // Right Pane: Selected Session Detail & Notes Editor
            if let session = selectedSession {
                SessionDetailView(model: model, session: session)
                    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.3))

                    Text("Chọn một cuộc họp để xem chi tiết")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("Bạn có thể xem lại lời thoại song ngữ, ghi chép hành động (action items), và xuất ra Word (.docx) hoặc Text (.txt).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            }
        }
        .confirmationDialog(
            "Xóa cuộc họp này khỏi sổ tay?",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Xóa vĩnh viễn", role: .destructive) {
                if let s = sessionToDelete {
                    model.deleteSession(id: s.id)
                    sessionToDelete = nil
                }
            }
            Button("Hủy", role: .cancel) {
                sessionToDelete = nil
            }
        } message: {
            if let s = sessionToDelete {
                Text("Hành động này sẽ xóa toàn bộ bản dịch song ngữ và ghi chú của \"\(s.title)\".")
            }
        }
            } else {
                VocabularyNotebookSectionView()
            }
        }
    }
}

// MARK: - Session Row Item

private struct SessionRowItem: View {
    let session: MeetingSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var formattedTime: String {
        let timeDF = DateFormatter()
        timeDF.locale = Locale(identifier: "vi_VN")
        timeDF.dateFormat = "HH:mm"
        let timeStr = timeDF.string(from: session.createdAt)

        if Calendar.current.isDateInToday(session.createdAt) {
            return "\(timeStr) • Hôm nay"
        } else if Calendar.current.isDateInYesterday(session.createdAt) {
            return "\(timeStr) • Hôm qua"
        } else {
            let dateDF = DateFormatter()
            dateDF.locale = Locale(identifier: "vi_VN")
            dateDF.dateFormat = "dd/MM/yy"
            return "\(timeStr) • \(dateDF.string(from: session.createdAt))"
        }
    }

    var durationText: String {
        let mins = Int(session.durationSeconds) / 60
        let secs = Int(session.durationSeconds) % 60
        if mins > 0 {
            return "\(mins)p\(secs)s"
        } else {
            return "\(secs)s"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Leading accent strip or icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? TransToolsTheme.navy.opacity(0.2) : Color.secondary.opacity(0.1))
                        .frame(width: 32, height: 32)

                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? TransToolsTheme.navy : Color.secondary)
                }

                // Title & Metadata
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.88))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(formattedTime)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Text("•")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary.opacity(0.5))

                        Text("\(session.captions.count) câu")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)

                        if !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary.opacity(0.5))
                            Image(systemName: "pencil.and.scribble")
                                .font(.system(size: 9))
                                .foregroundStyle(.purple)
                        }
                    }
                }

                Spacer(minLength: 4)

                // Delete button on hover
                if isHovered || isSelected {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(5)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Xóa cuộc họp này")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? TransToolsTheme.navy.opacity(0.12) : (isHovered ? Color.secondary.opacity(0.06) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? TransToolsTheme.navy.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Session Detail View

private struct SessionDetailView: View {
    @ObservedObject var model: MeetingModel
    let session: MeetingSession
    @State private var isEditingTitle = false
    @State private var editableTitle = ""
    @State private var notesText = ""
    @State private var transcriptQuery = ""
    @State private var isNotesExpanded = false
    @State private var copiedConfirmation = false

    @State private var showActionItemsSheet = false

    var filteredCaptions: [CaptionRecord] {
        if transcriptQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return session.captions
        }
        let q = transcriptQuery.lowercased()
        return session.captions.filter {
            $0.original.lowercased().contains(q) || $0.vietnamese.lowercased().contains(q)
        }
    }

    var formattedFullDate: String {
        let timeDF = DateFormatter()
        timeDF.locale = Locale(identifier: "vi_VN")
        timeDF.dateFormat = "HH:mm"
        let timeStr = timeDF.string(from: session.createdAt)

        let dateDF = DateFormatter()
        dateDF.locale = Locale(identifier: "vi_VN")
        dateDF.dateFormat = "EEEE, dd/MM/yyyy"
        let dateStr = dateDF.string(from: session.createdAt)

        return "\(timeStr) • \(dateStr)"
    }

    var formattedDuration: String {
        let mins = Int(session.durationSeconds) / 60
        let secs = Int(session.durationSeconds) % 60
        if mins > 0 {
            return "\(mins) phút \(secs) giây"
        } else {
            return "\(secs) giây"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Action Header
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                // Editable Title
                if isEditingTitle {
                    TextField("Tiêu đề cuộc họp", text: $editableTitle, onCommit: {
                        let trimmed = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            model.updateSessionTitle(id: session.id, title: trimmed)
                        }
                        isEditingTitle = false
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16, weight: .bold))

                    Button("Lưu") {
                        let trimmed = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            model.updateSessionTitle(id: session.id, title: trimmed)
                        }
                        isEditingTitle = false
                    }
                    .buttonStyle(TransToolsActionButtonStyle(prominent: true))
                    .tint(.purple)
                    .controlSize(.small)
                } else {
                    HStack(spacing: 6) {
                        Text(session.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .lineLimit(1)

                        Button {
                            editableTitle = session.title
                            isEditingTitle = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .help("Đổi tên cuộc họp")
                    }
                }

                Spacer()

                }
                // Keep actions on a separate row so long titles cannot squeeze button labels.
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                if session.audioSource == "Luyện nói với AI" {
                    Button {
                        model.pendingConversationID = session.id
                        model.selectedDashboardTab = 5
                    } label: { Label("Tiếp tục trò chuyện", systemImage: "bubble.left.and.bubble.right") }
                    .buttonStyle(SettingsActionButtonStyle())
                }

                    // Extract Action Items (AI)
                    Button {
                        showActionItemsSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checklist")
                                .font(.system(size: 12))
                            Text("Việc cần làm (AI)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(minHeight: 40)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Trích xuất việc cần làm (Action Items) từ cuộc họp và thêm vào Nhắc nhở")

                    // Export to Word (.docx)
                    Button {
                        model.exportSessionToDocx(session)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.richtext.fill")
                                .font(.system(size: 12))
                            Text("Xuất Word")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(minHeight: 40)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.1, green: 0.45, blue: 0.9), Color(red: 0.05, green: 0.35, blue: 0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: TransToolsTheme.accent.opacity(0.25), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .help("Xuất toàn bộ biên bản cuộc họp và bảng hội thoại song ngữ sang file Microsoft Word (.docx)")

                    // Export to TXT
                    Button {
                        model.exportSessionToTxt(session)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 12))
                            Text("Xuất TXT")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(minHeight: 40)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Xuất ra file văn bản thuần (.txt)")
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 3)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            .overlay(Divider().opacity(0.5), alignment: .bottom)
            .sheet(isPresented: $showActionItemsSheet) {
                MeetingActionItemsSheetView(session: session, model: model)
            }

            // Content Scroll
            ScrollView {
                VStack(spacing: 16) {
                    // Session Metadata Strip
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            MetaBadge(icon: "calendar", label: formattedFullDate, color: .blue)
                            MetaBadge(icon: "clock", label: formattedDuration, color: .orange)
                            MetaBadge(icon: "speaker.wave.2", label: session.audioSource, color: .green)
                            MetaBadge(icon: "text.bubble", label: "\(session.captions.count) đoạn phụ đề", color: .purple)
                        }
                    }
                    .padding(.top, 4)

                    // Personal Notes & Action Items Box (Mặc định thu gọn, bấm để mở rộng)
                    VStack(alignment: .leading, spacing: isNotesExpanded ? 10 : 0) {
                        HStack {
                            Label("Ghi chú & Hành động (Action Items)", systemImage: "note.text")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.purple)

                            if !notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isNotesExpanded {
                                Text("• Đã có ghi chú")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.purple)
                            }

                            Spacer()

                            Text(isNotesExpanded ? "Tự động lưu khi nhập" : "Bấm để mở")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isNotesExpanded.toggle()
                                }
                            } label: {
                                Image(systemName: isNotesExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isNotesExpanded.toggle()
                            }
                        }

                        if isNotesExpanded {
                            TextEditor(text: $notesText)
                                .font(.system(size: 12, design: .default))
                                .frame(minHeight: 80, maxHeight: 160)
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(TransToolsTheme.navy.opacity(0.2), lineWidth: 1)
                                )
                                .onChange(of: notesText) { _, newValue in
                                    model.updateSessionNotes(id: session.id, notes: newValue)
                                }
                        }
                    }
                    .padding(12)
                    .background(TransToolsTheme.navy.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(TransToolsTheme.navy.opacity(0.18), lineWidth: 1)
                    )

                    // Bilingual Dialogue Section Header & Search
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Text("Bản ghi thoại song ngữ")
                                .font(.system(size: 14, weight: .bold))
                            Text("(\(filteredCaptions.count))")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Filter within dialogue
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)

                            TextField("Lọc câu thoại...", text: $transcriptQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .frame(width: 130)

                            if !transcriptQuery.isEmpty {
                                Button {
                                    transcriptQuery = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }

                    // Dialogue Cards List
                    if filteredCaptions.isEmpty {
                        VStack(spacing: 8) {
                            Text("Không có câu thoại nào phù hợp.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 30)
                        }
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(filteredCaptions.enumerated()), id: \.element.id) { index, item in
                                NotebookCaptionCard(index: index + 1, item: item)
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            notesText = session.notes
            editableTitle = session.title
        }
        .onChange(of: session.id) { _, _ in
            notesText = session.notes
            editableTitle = session.title
        }
    }
}

// MARK: - Metadata Badge Component

private struct MetaBadge: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .fixedSize()
    }
}

// MARK: - Notebook Caption Card

private struct NotebookCaptionCard: View {
    let index: Int
    let item: CaptionRecord
    @ObservedObject private var tts = TTSService.shared
    @State private var isHovered = false
    @State private var copiedText: String? = nil

    var timestampString: String {
        MeetingModel.timestamp(item.start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Card Header: Index & Timestamp & Quick Copy
            HStack(spacing: 8) {
                Text("#\(index)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.8))

                Text(timestampString)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                if tts.isSpeaking && (tts.currentlySpeakingText == item.original || tts.currentlySpeakingText == item.vietnamese) {
                    HStack(spacing: 3) {
                        Image(systemName: "speaker.wave.3.fill")
                        Text("Đang đọc…")
                            .font(.system(size: 9.5, weight: .bold))
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(TransToolsTheme.navy)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(TransToolsTheme.navy.opacity(0.12))
                    .clipShape(Capsule())
                }

                Spacer()

                if isHovered {
                    HStack(spacing: 4) {
                        let isSpeakingOrig = tts.isSpeaking && tts.currentlySpeakingText == item.original
                        Button {
                            if isSpeakingOrig {
                                tts.stop()
                            } else {
                                tts.speak(text: item.original, language: .english)
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isSpeakingOrig ? "speaker.wave.3.fill" : "speaker.wave.2")
                                Text("Gốc")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isSpeakingOrig ? TransToolsTheme.navy : .primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(isSpeakingOrig ? TransToolsTheme.navy.opacity(0.15) : Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Nghe phát âm tiếng gốc")

                        Button {
                            copy(item.original)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.on.doc")
                                Text("Gốc")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Sao chép câu thoại gốc")

                        if !item.vietnamese.isEmpty {
                            let isSpeakingTrans = tts.isSpeaking && tts.currentlySpeakingText == item.vietnamese
                            Button {
                                if isSpeakingTrans {
                                    tts.stop()
                                } else {
                                    tts.speak(text: item.vietnamese, language: .vietnamese)
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: isSpeakingTrans ? "speaker.wave.3.fill" : "speaker.wave.2")
                                    Text("Dịch")
                                }
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isSpeakingTrans ? TransToolsTheme.navy : .primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(isSpeakingTrans ? TransToolsTheme.navy.opacity(0.15) : Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help("Nghe bản dịch tiếng Việt")

                            Button {
                                copy(item.vietnamese)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "doc.on.doc")
                                    Text("Dịch")
                                }
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help("Sao chép bản dịch")
                        }

                        Button {
                            copy("[\(timestampString)]\n[Gốc]: \(item.original)\n[Dịch]: \(item.vietnamese)")
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Tất cả")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(TransToolsTheme.navy.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Sao chép cả câu thoại và bản dịch")
                    }
                }
            }

            // English Original
            Text(item.original)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            // Vietnamese Translation
            if !item.vietnamese.isEmpty {
                Text(item.vietnamese)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.blue)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isHovered ? TransToolsTheme.navy.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - AI Action Items Sheet View

struct MeetingActionItemsSheetView: View {
    let session: MeetingSession
    @ObservedObject var model: MeetingModel
    @Environment(\.dismiss) private var dismiss

    @StateObject private var extractor = MeetingTaskExtractorService.shared
    @State private var items: [MeetingActionItem] = []
    @State private var newTodoText: String = ""
    @State private var exportStatusMessage: String = ""
    @State private var isExporting: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(TransToolsTheme.navy)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Việc cần làm sau cuộc họp (AI)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(session.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(TransToolsTheme.mint)

            Divider()

            // Content
            if extractor.isExtracting {
                VStack(spacing: 14) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Đang phân tích biên bản và trích xuất nhiệm vụ...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("Chưa tìm thấy đầu việc nào từ cuộc họp")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button("Phân tích tự động lại") {
                        Task {
                            await runExtraction()
                        }
                    }
                    .buttonStyle(TransToolsActionButtonStyle(prominent: true))
                    .tint(TransToolsTheme.navy)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($items) { $item in
                            HStack(spacing: 10) {
                                Button(action: {
                                    item.isCompleted.toggle()
                                }) {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                                }
                                .buttonStyle(.plain)

                                TextField("Nội dung việc", text: $item.title)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13, weight: item.isCompleted ? .regular : .medium))
                                    .strikethrough(item.isCompleted)
                                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                                if !item.assignee.isEmpty {
                                    Text(item.assignee)
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(TransToolsTheme.navy.opacity(0.12))
                                        .foregroundStyle(TransToolsTheme.navy)
                                        .clipShape(Capsule())
                                }

                                Button(action: {
                                    items.removeAll { $0.id == item.id }
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .transToolsPanel()
                        }

                        // Add new item input
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(TransToolsTheme.navy)
                            TextField("Thêm việc cần làm thủ công...", text: $newTodoText, onCommit: {
                                let trimmed = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    items.append(MeetingActionItem(title: trimmed, assignee: "Tôi"))
                                    newTodoText = ""
                                }
                            })
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))

                            if !newTodoText.isEmpty {
                                Button("Thêm") {
                                    let trimmed = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty {
                                        items.append(MeetingActionItem(title: trimmed, assignee: "Tôi"))
                                        newTodoText = ""
                                    }
                                }
                                .font(.system(size: 11, weight: .bold))
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(16)
                }
            }

            Divider()

            // Footer
            HStack(spacing: 12) {
                if !exportStatusMessage.isEmpty {
                    Text(exportStatusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                }

                Spacer()

                Button("Phân tích lại") {
                    Task {
                        await runExtraction()
                    }
                }
                .buttonStyle(TransToolsActionButtonStyle())
                .disabled(extractor.isExtracting)

                Button(action: exportToReminders) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.plus")
                        Text("Xuất vào Nhắc nhở")
                    }
                }
                .buttonStyle(TransToolsActionButtonStyle(prominent: true))
                .tint(TransToolsTheme.navy)
                .disabled(items.isEmpty || extractor.isExtracting)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(TransToolsTheme.mint)
        }
        .frame(width: 640, height: 500)
        .onAppear {
            Task {
                await runExtraction()
            }
        }
    }

    private func runExtraction() async {
        let extracted = await extractor.extractActionItems(
            from: session,
            model: model
        )
        self.items = extracted
    }

    private func exportToReminders() {
        let success = extractor.exportToAppleReminders(items: items, sessionTitle: session.title)
        if success {
            exportStatusMessage = "✓ Đã thêm vào ứng dụng Nhắc nhở (Reminders)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                exportStatusMessage = ""
            }
        } else {
            exportStatusMessage = "✕ Không thể đồng bộ với Reminders"
        }
    }
}
