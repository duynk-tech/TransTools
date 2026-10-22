import SwiftUI

struct MeetingNotesSheetView: View {
    @ObservedObject var model: MeetingModel
    let session: MeetingSession
    @Binding var notes: String
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var generating = false
    @State private var generationTask: Task<Void, Never>?
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Ghi chú", systemImage: "note.text")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(TransToolsTheme.accent)
                Spacer()
                Button("Đóng") { dismiss() }
                    .buttonStyle(TransToolsActionButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            Text(session.title).font(.system(size: 13)).foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 10) {
                Button {
                    generateNotes()
                } label: {
                    Label(generating ? "Đang tạo…" : "Tạo ghi chú AI", systemImage: "sparkles")
                }
                .buttonStyle(TransToolsActionButtonStyle(prominent: true))
                .disabled(generating || model.configuredAI == nil || session.captions.isEmpty)
                if generating {
                    ProgressView().controlSize(.small)
                    Button("Hủy") { generationTask?.cancel(); generating = false }
                        .buttonStyle(TransToolsActionButtonStyle())
                }
                Spacer()
                Button(editing ? "Xem Markdown" : "Chỉnh sửa") { editing.toggle() }
                    .buttonStyle(TransToolsActionButtonStyle())
            }
            Group {
                if editing {
                    TextEditor(text: $notes)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                } else {
                    ScrollView {
                        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Chưa có ghi chú. Bạn có thể tạo bằng AI hoặc tự viết.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            MeetingNotesMarkdownView(source: notes)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TransToolsTheme.accent.opacity(0.3)))
            if !message.isEmpty { Text(message).font(.system(size: 12)).foregroundStyle(.secondary) }
            if model.configuredAI == nil {
                Text("Thêm API key và chọn mô hình trong AI & Kết nối để tạo ghi chú.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text(editing ? "Tự động lưu khi nhập · Hỗ trợ Markdown" : "AI tạo từ bản ghi và thêm vào cuối ghi chú hiện có. Hãy kiểm tra lại nội dung.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if let error = model.storageError {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 720, height: 560)
        .background(TransToolsTheme.background)
        .onChange(of: notes) { _, value in model.updateSessionNotes(id: session.id, notes: value) }
        .onDisappear { generationTask?.cancel() }
    }

    private func generateNotes() {
        guard !generating, let ai = model.configuredAI else { return }
        let transcript = session.captions.filter { !$0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "[\(MeetingModel.timestamp($0.start))] \($0.original)" }.joined(separator: "\n")
        guard !transcript.isEmpty else { message = "Bản ghi chưa có nội dung để tạo ghi chú."; return }
        let domain = model.domainSpecialty
        let initialNotes = notes
        generating = true
        message = ""
        generationTask = Task { @MainActor in
            do {
                let result = try await AITranslator.summarizeMeeting(transcript, domain: domain,
                    provider: ai.provider, model: ai.model, key: ai.key)
                guard !Task.isCancelled else { return }
                // Use the latest saved notes, including edits made while the request ran.
                guard let latest = model.sessions.first(where: { $0.id == session.id }) else {
                    generating = false; message = "Bản ghi này không còn trong Sổ tay."; return
                }
                let existing = notes == initialNotes ? latest.notes : notes
                notes = existing + (existing.isEmpty ? "" : "\n\n---\n\n") + result
                editing = false
                message = "Đã thêm ghi chú AI."
            } catch {
                guard !Task.isCancelled else { return }
                message = "Chưa tạo được ghi chú: " + error.localizedDescription
            }
            generating = false
        }
    }
}

/// Native Markdown display: no HTML, web view or remotely loaded images.
private struct MeetingNotesMarkdownView: View {
    let source: String
    private var lines: [(text: String, code: Bool)] {
        var code = false
        return source.components(separatedBy: .newlines).compactMap { line in
            if line.hasPrefix("```") { code.toggle(); return nil }
            return (line, code)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, entry in
                let line = entry.text
                if entry.code {
                    Text(line).font(.system(size: 13, design: .monospaced))
                        .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                        .background(TransToolsTheme.mint)
                } else if line == "---" || line == "***" {
                    Divider().padding(.vertical, 4)
                } else if line.isEmpty {
                    Color.clear.frame(height: 4)
                } else {
                    formattedLine(line)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func formattedLine(_ line: String) -> some View {
        let heading = line.prefix(while: { $0 == "#" }).count
        let isHeading = (1...6).contains(heading) && line.dropFirst(heading).hasPrefix(" ")
        let checked = line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ")
        let task = checked || line.hasPrefix("- [ ] ")
        let bullet = line.hasPrefix("- ") || line.hasPrefix("* ")
        let quote = line.hasPrefix("> ")
        let body = isHeading ? String(line.dropFirst(heading + 1)) : task ? String(line.dropFirst(6)) : bullet || quote ? String(line.dropFirst(2)) : line
        let attributed = (try? AttributedString(markdown: body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(body)
        return HStack(alignment: .top, spacing: 8) {
            if task {
                Image(systemName: checked ? "checkmark.square" : "square").foregroundStyle(TransToolsTheme.accent)
            } else if bullet {
                Text("•").foregroundStyle(TransToolsTheme.accent)
            } else if quote {
                RoundedRectangle(cornerRadius: 2).fill(TransToolsTheme.accent.opacity(0.5)).frame(width: 3)
            }
            Text(attributed)
                .font(.system(size: isHeading ? (heading == 1 ? 22 : heading == 2 ? 18 : 16) : 14,
                              weight: isHeading ? .bold : .regular))
                .foregroundStyle(isHeading ? TransToolsTheme.accent : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
