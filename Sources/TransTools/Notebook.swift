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
                        .font(.system(size: 13, weight: .semibold))
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
    @State private var appliedSearch = ""
    @State private var searchMatches: Set<UUID> = []
    @State private var transcriptSearch = ""
    @State private var sessionToDelete: MeetingSession? = nil
    @State private var confirmDeleteAll = false
    @State private var deletionIDs: Set<UUID> = []
    @State private var isEditingNotes = false
    @State private var sessionFilter = 0
    @State private var compactDetail = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let dateGroups = ["Hôm nay", "Hôm qua", "Trước đó"]
    private func dateGroup(_ session: MeetingSession) -> String {
        Calendar.current.isDateInToday(session.createdAt) ? "Hôm nay" : Calendar.current.isDateInYesterday(session.createdAt) ? "Hôm qua" : "Trước đó"
    }

    var filteredSessions: [MeetingSession] {
        let q = appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.sessions.filter { session in
            let chat = session.audioSource == "Luyện nói với AI"
            let matchesType = sessionFilter == 0 || (sessionFilter == 1 && !chat) || (sessionFilter == 2 && chat)
            guard matchesType else { return false }
            guard !q.isEmpty else { return true }
            return searchMatches.contains(session.id)
        }.sorted { $0.createdAt > $1.createdAt }
    }
    var selectedSession: MeetingSession? {
        filteredSessions.first { $0.id == model.selectedSessionID } ?? filteredSessions.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Section Web-Style Tab Bar: Sổ tay cuộc họp vs Sổ từ vựng
            HStack(spacing: 4) {
                NotebookWebTabItem(
                    title: "Cuộc họp & Hội thoại",
                    icon: "bubble.left.and.text.bubble.right.fill",
                    count: model.sessions.count,
                    isSelected: model.selectedNotebookTab == 0
                ) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                        model.selectedNotebookTab = 0
                    }
                }

                NotebookWebTabItem(
                    title: "Từ vựng",
                    icon: "character.book.closed.fill",
                    count: vocabManager.items.count,
                    isSelected: model.selectedNotebookTab == 1
                ) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
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
                NotebookSplitLayout(showDetail: $compactDetail) {
            // Left Pane: Session List & Search
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("Tìm tiêu đề, ghi chú, lời thoại…", text: $searchText)
                        .help("Có thể tìm không dấu và nhập nhiều từ, ví dụ: tien do du an")
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if searchText != appliedSearch {
                        ProgressView().controlSize(.mini)
                            .accessibilityLabel("Đang tìm trong Sổ tay")
                    }

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
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)


                Divider().opacity(0.5)

                HStack(spacing: 0) {
                    ForEach(Array(["Tất cả", "Cuộc họp", "Trò chuyện"].enumerated()), id: \.offset) { index, title in
                        Button { sessionFilter = index } label: {
                            Text(title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .foregroundStyle(sessionFilter == index ? Color.white : TransToolsTheme.accent)
                                .background(sessionFilter == index ? TransToolsTheme.accent : Color.clear)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(sessionFilter == index ? .isSelected : [])
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(TransToolsTheme.accent.opacity(0.25), lineWidth: 1))
                .padding(12)
                // Sessions List
                if model.sessions.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        MiniAvatarView(size: 68, isHovered: false, time: 0)
                            .padding(12).background(TransToolsTheme.mint, in: Circle())
                            .accessibilityHidden(true)

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
                        Text("Không tìm thấy buổi phù hợp")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(dateGroups, id: \.self) { group in
                                let entries = filteredSessions.filter { dateGroup($0) == group }
                                if !entries.isEmpty {
                                    Text(group).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10).padding(.horizontal, 10)
                            ForEach(entries) { session in
                                SessionRowItem(
                                    session: session,
                                    isSelected: selectedSession?.id == session.id,
                                    onSelect: {
                                        model.selectedSessionID = session.id
                                        compactDetail = true
                                    },
                                    onDelete: {
                                        sessionToDelete = session
                                    }
                                )
                            }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                }
                HStack {
                    Text(searchText != appliedSearch ? "Đang tìm…" :
                        (!appliedSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sessionFilter != 0
                            ? "\(filteredSessions.count) / \(model.sessions.count) bản ghi"
                            : "\(model.sessions.count) bản ghi"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(role: .destructive) {
                        deletionIDs = Set(model.sessions.map(\.id))
                        confirmDeleteAll = true
                    } label: {
                        Label("Xóa tất cả", systemImage: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(TransToolsActionButtonStyle(height: 28))
                    .disabled(model.sessions.isEmpty || model.running)
                    .help("Xóa tất cả cuộc họp và hội thoại")
                    .accessibilityLabel("Xóa tất cả cuộc họp và hội thoại")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                if model.lastDeletedNotebookSession != nil || !model.lastDeletedNotebookSessions.isEmpty {
                    HStack {
                        Text(model.lastDeletedNotebookSessions.isEmpty ? "Đã xóa bản ghi" : "Đã xóa \(model.lastDeletedNotebookSessions.count) bản ghi").font(.caption)
                        Spacer()
                        Button("Hoàn tác") { model.undoNotebookDeletion() }
                            .buttonStyle(TransToolsActionButtonStyle(height: 30))
                    }.padding(10).background(TransToolsTheme.mint)
                }
                if let storageError = model.storageError, !storageError.isEmpty {
                    Text(storageError).font(.caption).foregroundStyle(.red).padding(10)
                }
            }
            .frame(minWidth: 260, idealWidth: 300)
            .background(TransToolsTheme.background.opacity(0.78))

            } detail: {
            // Right Pane: Selected Session Detail & Notes Editor
            if let session = selectedSession {
                SessionDetailView(model: model, session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Button("Xóa", role: .destructive) {
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
                Text("Xóa bản ghi và ghi chú của \"\(s.title)\".")
            }
        }
        .alert("Xóa tất cả cuộc họp và hội thoại?", isPresented: $confirmDeleteAll) {
            Button("Hủy", role: .cancel) { deletionIDs = [] }
            Button("Xóa tất cả", role: .destructive) {
                model.deleteNotebookSessions(ids: deletionIDs)
                deletionIDs = []
                compactDetail = false
            }
        } message: {
            Text("Bạn sẽ xóa \(deletionIDs.count) bản ghi cùng lời thoại và ghi chú, kể cả bản ghi đang bị ẩn bởi bộ lọc. Từ vựng không bị xóa. Có thể bấm Hoàn tác ngay sau khi xóa, trước khi đóng app hoặc xóa tiếp.")
        }
            } else {
                VocabularyNotebookSectionView()
            }
        }
        .task(id: NotebookSearch.Request(text: searchText, sessions: model.sessions)) {
            let request = NotebookSearch.Request(text: searchText, sessions: model.sessions)
            let pending = request.text
            if !pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            do {
                let matches = pending.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? Set<UUID>() : try await NotebookSearch.sessionIDs(for: request)
                try Task.checkCancellation()
                guard searchText == pending, model.sessions == request.sessions else { return }
                searchMatches = matches
                appliedSearch = pending
            } catch is CancellationError {
                // A new query owns the results; keep the previous list until it is ready.
            } catch { }
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
                        .fill(isSelected ? TransToolsTheme.accent.opacity(0.2) : Color.secondary.opacity(0.1))
                        .frame(width: 32, height: 32)

                    Image(systemName: session.audioSource == "Luyện nói với AI" ? "bubble.left.and.bubble.right" : "waveform")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? TransToolsTheme.accent : Color.secondary)
                }

                // Title & Metadata
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.88))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(formattedTime)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text("•")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary.opacity(0.5))

                        Text(durationText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)

                        if !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary.opacity(0.5))
                            Image(systemName: "pencil.and.scribble")
                                .font(.system(size: 9))
                                .foregroundStyle(TransToolsTheme.accent)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Reserve the action slot so hover never changes the text width.
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .padding(5)
                            .background(Color.red.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Xóa cuộc họp này")
                    .frame(width: 24, height: 24)
                    .opacity(isHovered || isSelected ? 1 : 0)
                    .allowsHitTesting(isHovered || isSelected)
                    .accessibilityHidden(!isHovered && !isSelected)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? TransToolsTheme.accent.opacity(0.12) : (isHovered ? Color.secondary.opacity(0.06) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isHovered ? TransToolsTheme.accent.opacity(0.65) : (isSelected ? TransToolsTheme.accent.opacity(0.3) : Color.clear), lineWidth: 1)
                    .allowsHitTesting(false)
            )
        }
        .buttonStyle(.plain)
        .animation(nil, value: isHovered)
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
    @State private var appliedTranscriptQuery = ""
    @State private var transcriptMatches: Set<UUID> = []
    @State private var matchedTranscriptSession: UUID?
    @State private var showNotesSheet = false
    @State private var copiedConfirmation = false
    @AppStorage("Notebook_DisplayMode") private var displayMode = 0
    @AppStorage("Notebook_FontSize") private var readingSize = 14.0
    @State private var exportError = ""

    @State private var showActionItemsSheet = false

    private var transcriptTitle: some View {
        HStack(spacing: 8) {
            Text("Bản ghi").font(.system(size: 14, weight: .bold))
            Text("\(filteredCaptionIndices.count)")
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .padding(.horizontal, 7).padding(.vertical, 4)
                .foregroundStyle(TransToolsTheme.accent)
                .background(TransToolsTheme.mint, in: Capsule())
        }.fixedSize()
    }

    private var transcriptModes: some View {
        HStack(spacing: 0) {
            ForEach(0..<3) { mode in
                Button { displayMode = mode } label: {
                    Text(["Song ngữ", "Tiếng gốc", "Bản dịch"][mode])
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 84, height: 32)
                        .foregroundStyle(displayMode == mode ? Color.white : TransToolsTheme.accent)
                        .background(displayMode == mode ? TransToolsTheme.accent : Color.clear)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(displayMode == mode ? .isSelected : [])
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TransToolsTheme.accent.opacity(0.25)))
        .accessibilityLabel("Ngôn ngữ bản ghi")
    }

    private var transcriptFontSize: some View {
        HStack(spacing: 0) {
            Button { readingSize = max(12, readingSize - 1) } label: {
                Image(systemName: "textformat.size.smaller").frame(width: 30, height: 32)
            }
            .disabled(readingSize <= 12).help("Giảm cỡ chữ")
            .accessibilityLabel("Giảm cỡ chữ")
            Text("\(Int(readingSize))").font(.system(size: 12, weight: .medium))
                .monospacedDigit().frame(width: 24)
                .accessibilityLabel("Cỡ chữ \(Int(readingSize))")
            Button { readingSize = min(22, readingSize + 1) } label: {
                Image(systemName: "textformat.size.larger").frame(width: 30, height: 32)
            }
            .disabled(readingSize >= 22).help("Tăng cỡ chữ")
            .accessibilityLabel("Tăng cỡ chữ")
        }
        .buttonStyle(.plain)
        .foregroundStyle(TransToolsTheme.accent)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TransToolsTheme.accent.opacity(0.25)))
        .fixedSize()
    }

    private var transcriptSearch: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(TransToolsTheme.accent)
            TextField("Tìm trong bản ghi…", text: $transcriptQuery)
                .textFieldStyle(.plain)
                .accessibilityLabel("Tìm trong bản ghi")
            if transcriptSearchPending {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel("Đang tìm trong bản ghi")
            }
            Button { transcriptQuery = "" } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .opacity(transcriptQuery.isEmpty ? 0 : 1)
            .disabled(transcriptQuery.isEmpty)
            .accessibilityLabel("Xóa tìm kiếm")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(width: 185, height: 32)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(TransToolsTheme.accent.opacity(0.25)))
    }

    private func exportSRT() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Bản ghi.srt"
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = NotebookSubtitleExport.content(captions: session.captions, mode: displayMode)
        do { try content.write(to: url, atomically: true, encoding: .utf8); exportError = "" }
        catch { exportError = "Chưa xuất được phụ đề: " + error.localizedDescription }
    }

    private var transcriptSearchPending: Bool {
        !transcriptQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (appliedTranscriptQuery != transcriptQuery || matchedTranscriptSession != session.id)
    }

    var filteredCaptionIndices: [Int] {
        if transcriptQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NotebookSearch.captionIndices(in: session.captions, matching: nil)
        }
        guard matchedTranscriptSession == session.id else { return [] }
        return NotebookSearch.captionIndices(in: session.captions, matching: transcriptMatches)
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
                    .tint(TransToolsTheme.accent)
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
                    .buttonStyle(TransToolsActionButtonStyle(prominent: true))
                }

                    // Extract Action Items (AI)
                    if session.audioSource != "Luyện nói với AI" {
                    Button {
                        showActionItemsSheet = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checklist")
                                .font(.system(size: 12))
                            Text("Việc cần làm (AI)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(TransToolsActionButtonStyle())
                    .help("Trích xuất việc cần làm (Action Items) từ cuộc họp và thêm vào Nhắc nhở")
                    }
                    Button {
                        notesText = model.sessions.first(where: { $0.id == session.id })?.notes ?? session.notes
                        showNotesSheet = true
                    } label: {
                        Label("Ghi chú", systemImage: notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "note.text" : "note.text.badge.plus")
                    }
                    .buttonStyle(TransToolsActionButtonStyle())
                    .help("Xem và chỉnh sửa ghi chú")
                    Menu {
                        Button("Word (.docx)") { model.exportSessionToDocx(session) }
                        Button("Văn bản (.txt)") { model.exportSessionToTxt(session) }
                        Button("Phụ đề (.srt)") { exportSRT() }
                    } label: { Label("Xuất", systemImage: "square.and.arrow.up") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .padding(.horizontal, 14).frame(height: 40)
                    .background(TransToolsTheme.mint, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TransToolsTheme.accent.opacity(0.25)))
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.vertical, 3)
                }
                    // Session Metadata Strip
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            MetaBadge(icon: "calendar", label: formattedFullDate, color: TransToolsTheme.accent)
                            MetaBadge(icon: "clock", label: formattedDuration, color: TransToolsTheme.accent)
                            MetaBadge(icon: "speaker.wave.2", label: session.audioSource, color: TransToolsTheme.accent)
                            MetaBadge(icon: "text.bubble", label: "\(session.captions.count) đoạn phụ đề", color: TransToolsTheme.accent)
                        }
                    }
                    .padding(.top, 4)


            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            .overlay(Divider().opacity(0.5), alignment: .bottom)
            .sheet(isPresented: $showActionItemsSheet) {
                MeetingActionItemsSheetView(session: session, model: model)
            }
            .sheet(isPresented: $showNotesSheet) {
                MeetingNotesSheetView(model: model, session: session, notes: $notesText)

            }


            // Notes live in a sheet so the transcript keeps its reading space.
            // Content Scroll
            ScrollView {
                VStack(spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            transcriptTitle
                            Spacer(minLength: 12)
                            transcriptModes
                            transcriptFontSize
                            transcriptSearch
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                transcriptTitle
                                Spacer()
                                transcriptSearch
                            }
                            HStack(spacing: 12) {
                                transcriptModes
                                Spacer(minLength: 0)
                                transcriptFontSize
                            }
                        }
                    }
                    .padding(12)
                    .background(TransToolsTheme.mint.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TransToolsTheme.accent.opacity(0.18)))
                    if !exportError.isEmpty { Text(exportError).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    // Dialogue Cards List
                    let captionIndices = filteredCaptionIndices
                    if captionIndices.isEmpty {
                        VStack(spacing: 8) {
                            Text(transcriptSearchPending ? "Đang tìm trong bản ghi…" : "Không có câu thoại nào phù hợp.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 30)
                        }
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(captionIndices, id: \.self) { index in
                                NotebookCaptionCard(index: index + 1, item: session.captions[index], displayMode: displayMode, readingSize: readingSize)
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .background(TransToolsTheme.background.opacity(0.78))
        .task(id: NotebookSearch.TranscriptRequest(text: transcriptQuery, sessionID: session.id, captions: session.captions)) {
            let request = NotebookSearch.TranscriptRequest(text: transcriptQuery, sessionID: session.id, captions: session.captions)
            do {
                if !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try await Task.sleep(for: .milliseconds(200))
                }
                let ids = request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? Set<UUID>() : try await NotebookSearch.captionIDs(for: request)
                try Task.checkCancellation()
                guard transcriptQuery == request.text, session.id == request.sessionID, session.captions == request.captions else { return }
                transcriptMatches = ids
                matchedTranscriptSession = request.sessionID
                appliedTranscriptQuery = request.text
            } catch is CancellationError { }
            catch { }
        }
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
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .fixedSize()
    }
}

// MARK: - Notebook Caption Card

private struct NotebookCaptionCard: View {
    let index: Int
    let item: CaptionRecord
    var displayMode = 0
    var readingSize = 14.0
    @ObservedObject private var tts = TTSService.shared
    @State private var isHovered = false
    @State private var copyFeedback = false
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

                // Keep controls mounted so hover changes appearance, never layout.
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
                                Text("Nghe gốc")
                            }
                        }
                        .buttonStyle(TransToolsActionButtonStyle(height: 26))
                        .help("Nghe phát âm tiếng gốc")

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
                                    Text("Nghe dịch")
                                }
                            }
                            .buttonStyle(TransToolsActionButtonStyle(height: 26))
                            .help("Nghe bản dịch tiếng Việt")

                        }

                        Menu {
                            Button("Tiếng gốc") { copy(item.original) }
                            if !item.vietnamese.isEmpty {
                                Button("Bản dịch") { copy(item.vietnamese) }
                                Button("Song ngữ kèm thời gian") {
                                    copy("[\(timestampString)]\n[Gốc]: \(item.original)\n[Dịch]: \(item.vietnamese)")
                                }
                            }
                        } label: {
                            Label("Sao chép", systemImage: "doc.on.doc")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 8)
                                .frame(height: 26)
                                .foregroundStyle(TransToolsTheme.accent)
                                .background(TransToolsTheme.accent.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(TransToolsTheme.accent.opacity(0.2), lineWidth: 1))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Chọn nội dung cần sao chép")
                    }
                    .opacity(isHovered ? 1 : 0.8)
            }

            // English Original
            if displayMode != 2 || item.vietnamese.isEmpty {
            Text(item.original)
                .font(.system(size: readingSize, weight: .regular))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            }
            // Vietnamese Translation
            if displayMode != 1 && !item.vietnamese.isEmpty {
                Text(item.vietnamese)
                    .font(.system(size: readingSize, weight: .regular))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(TransToolsTheme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(TransToolsTheme.accent)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(TransToolsTheme.accent.opacity(isHovered ? 0.65 : 0.22), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .overlay(alignment: .bottomTrailing) {
            if copyFeedback { Text("Đã sao chép").font(.caption).padding(6).background(TransToolsTheme.mint, in: Capsule()).padding(8).allowsHitTesting(false) }
        }
        .task(id: copyFeedback) {
            if copyFeedback { try? await Task.sleep(for: .seconds(1.5)); if !Task.isCancelled { copyFeedback = false } }
        }
        .animation(nil, value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyFeedback = true
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
                            HStack(alignment: .top, spacing: 10) {
                                Button(action: {
                                    item.isCompleted.toggle()
                                }) {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                                }
                                .buttonStyle(.plain)

                                TextField("Nội dung việc", text: $item.title, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .lineLimit(1...8)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .layoutPriority(1)
                                    .font(.system(size: 13, weight: item.isCompleted ? .regular : .medium))
                                    .strikethrough(item.isCompleted)
                                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                                if !item.assignee.isEmpty {
                                    Text(item.assignee)
                                        .font(.system(size: 10, weight: .semibold))
                                        .fixedSize()
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
