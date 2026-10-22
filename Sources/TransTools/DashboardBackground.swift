import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor final class DashboardAppearance: ObservableObject {
    static let shared = DashboardAppearance()
    @Published var mode: String { didSet { UserDefaults.standard.set(mode, forKey: "DashboardBackgroundMode") } }
    @Published private(set) var image: NSImage?
    @Published var error: String?
    private var imageURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TransTools/Appearance/background.jpg")
    }
    private init() {
        mode = UserDefaults.standard.string(forKey: "DashboardBackgroundMode") ?? "auto"
        image = NSImage(contentsOf: imageURL)
        if mode == "photo", image == nil { mode = "auto" }
    }
    func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2560
                  ] as CFDictionary),
                  let data = NSBitmapImageRep(cgImage: thumbnail).representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: imageURL, options: .atomic)
            image = NSImage(cgImage: thumbnail, size: .zero)
            mode = "photo"
        } catch { self.error = "Không mở được ảnh. Hãy chọn ảnh JPG, PNG hoặc HEIC khác." }
    }
    func removePhoto() {
        do {
            if FileManager.default.fileExists(atPath: imageURL.path) {
                _ = try FileManager.default.trashItem(at: imageURL, resultingItemURL: nil)
            }
            image = nil; mode = "auto"
        } catch { self.error = "Chưa gỡ được ảnh nền. Bạn thử lại nhé." }
    }
}

struct DashboardBackground: View {
    @ObservedObject private var appearance = DashboardAppearance.shared
    var body: some View {
        GeometryReader { geometry in
            if appearance.mode == "photo", let image = appearance.image {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    .overlay(Color.white.opacity(0.68))
            } else if appearance.mode == "mint" {
                TransToolsTheme.background
            } else {
                MeetingGardenBackground(timeOfDay: appearance.mode)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct DashboardAppearanceMenu: View {
    @ObservedObject private var appearance = DashboardAppearance.shared
    var body: some View {
        Menu {
            ForEach([("auto", "Thiên nhiên theo giờ"), ("morning", "Buổi sáng"), ("noon", "Buổi trưa"), ("afternoon", "Buổi chiều"), ("night", "Buổi tối"), ("mint", "Mint đơn giản")], id: \.0) { mode, title in
                Button { appearance.mode = mode } label: {
                    if appearance.mode == mode { Label(title, systemImage: "checkmark") }
                    else { Text(title) }
                }
            }
            Divider()
            Button("Chọn ảnh từ máy…") { appearance.choosePhoto() }
            if appearance.image != nil {
                Button("Dùng ảnh đã chọn") { appearance.mode = "photo" }
                Button("Gỡ ảnh nền", role: .destructive) { appearance.removePhoto() }
            }
        } label: {
            Image(systemName: "photo.on.rectangle")
                .foregroundStyle(TransToolsTheme.accent)
                .frame(width: 36, height: 36)
                .background(TransToolsTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TransToolsTheme.accent.opacity(0.24)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Giao diện")
        .help("Chọn hoạt cảnh hoặc ảnh nền cho các tab")
        .alert("Ảnh nền", isPresented: Binding(get: { appearance.error != nil }, set: { if !$0 { appearance.error = nil } })) {
            Button("Đóng", role: .cancel) { appearance.error = nil }
        } message: { Text(appearance.error ?? "") }
    }
}
