import SwiftUI

/// Transparent desktop orbit. Animates only while opening or closing.
struct MascotFeatureWheel: View {
    @ObservedObject var model: MeetingModel
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var hoveredFeature: Int?
    @State private var rippleVisible = false
    private let titles = ["Cuộc họp", "Phụ đề", "Dịch nhanh", "Đọc văn bản", "Học ngôn ngữ", "Trò chuyện", "Sổ tay", "Cài đặt", "Mở Trans Tools"]
    private let icons = ["waveform", "captions.bubble", "character.bubble", "speaker.wave.2", "graduationcap", "bubble.left.and.bubble.right", "book.closed", "gearshape", "macwindow"]
    private let tabs: [Int?] = [nil, nil, 2, 6, 3, 5, 1, 4, nil]

    var body: some View {
        ZStack {
            Circle().stroke(TransToolsTheme.accent.opacity(0.4), lineWidth: 1)
                .frame(width: 244, height: 244)
                .scaleEffect(expanded ? 1 : 0.2)
                .opacity(expanded ? 1 : 0)
                .allowsHitTesting(false)
            Circle()
                .stroke(TransToolsTheme.accent.opacity(0.72), lineWidth: 5)
                .frame(width: 244, height: 244)
                .scaleEffect(rippleVisible ? 0.18 : 1)
                .opacity(rippleVisible ? 0.7 : 0)
                .blur(radius: 4)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.46), value: rippleVisible)
            .allowsHitTesting(false)
            ForEach(titles.indices, id: \.self) { index in
                let angle = Double(index) * 2 * .pi / Double(titles.count + 1) - .pi / 2
                Button { select(index) } label: {
                    Image(systemName: icons[index])
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(TransToolsTheme.accent)
                        .scaleEffect(!reduceMotion && hoveredFeature == index ? 1.12 : 1)
                        .offset(y: !reduceMotion && hoveredFeature == index ? -2 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.65), value: hoveredFeature == index)
                        .frame(width: 48, height: 48)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().strokeBorder(TransToolsTheme.accent.opacity(0.65), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
                .accessibilityLabel(index == 0 && model.running ? "Dừng cuộc họp" : titles[index])
                .accessibilityHint(index == 0 && model.running ? "Dừng cuộc họp và lưu bản ghi" : titles[index])
                .onContinuousHover { phase in
                    switch phase {
                    case .active:
                        if hoveredFeature != index { hoveredFeature = index }
                    case .ended:
                        if hoveredFeature == index { hoveredFeature = nil }
                    }
                }
                .overlay(alignment: .top) {
                    if hoveredFeature == index {
                        Text(index == 0 && model.running ? "Dừng cuộc họp" : titles[index])
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TransToolsTheme.accent)
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .padding(.bottom, 6)
                            .frame(height: 32)
                            .background(MascotTooltipBubble().fill(Color.white))
                            .overlay(MascotTooltipBubble().strokeBorder(TransToolsTheme.accent.opacity(0.4), lineWidth: 1))
                            // Move the entire bubble above the 48pt icon, including its arrow.
                            // An explicit offset avoids alignment guides being lost in conditional overlays.
                            .offset(y: -32)
                            .allowsHitTesting(false)
                    }
                }
                .zIndex(hoveredFeature == index ? 1 : 0)
                .scaleEffect(expanded ? 1 : 0.75)
                .offset(x: cos(angle) * (expanded ? 122 : 0), y: sin(angle) * (expanded ? 122 : 0))
                .opacity(expanded ? 1 : 0)
                .animation(reduceMotion ? nil : (expanded
                    ? .spring(response: 0.34, dampingFraction: 0.76).delay(Double(index) * 0.03)
                    : .easeIn(duration: 0.16)), value: expanded)
            }
            Button {
                close { model.hideFloatingMascot() }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.90, green: 0.22, blue: 0.25))
                    .frame(width: 48, height: 48)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().strokeBorder(TransToolsTheme.accent.opacity(0.65), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Tạm biệt \(MascotIdentity.name) · Ẩn mascot, app vẫn chạy nền")
            .accessibilityLabel("Tạm biệt \(MascotIdentity.name)")
            .offset(x: cos(Double(titles.count) * 2 * Double.pi / Double(titles.count + 1) - Double.pi / 2) * (expanded ? 122 : 0),
                    y: sin(Double(titles.count) * 2 * Double.pi / Double(titles.count + 1) - Double.pi / 2) * (expanded ? 122 : 0))
            .scaleEffect(expanded ? 1 : 0.3)
            .opacity(expanded ? 1 : 0)
            .animation(reduceMotion ? nil : (expanded
                ? .spring(response: 0.34, dampingFraction: 0.76).delay(Double(titles.count) * 0.03)
                : .easeIn(duration: 0.16)), value: expanded)
        }
        .frame(width: 360, height: 360)
        .task {
            // Let AppKit finish resizing the panel before animating the orbit.
            await Task.yield()
            guard !Task.isCancelled else { return }
            if !reduceMotion {
                rippleVisible = true
                withAnimation(.easeOut(duration: 0.46)) { rippleVisible = false }
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { expanded = true }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { rippleVisible = false }
        }
    }

    private func close(then action: (() -> Void)? = nil) {
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.16)) { expanded = false }
        Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(180)) }
            isPresented = false
            // Let the collapsed mascot layout and AppKit window frame settle
            // before positioning an anchored mini panel around it.
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 32 : 72))
            action?()
        }
    }

    private func select(_ index: Int) {
        close {
            if index == 8 {
                model.showMainWindow()
            } else if let tab = tabs[index] {
                if let tool = MascotMiniTool(rawValue: tab) { model.miniTools.show(tool, model: model) }
            } else if index == 0 {
                Task {
                    if model.running { await model.stop() }
                    else { await model.startFromMascot() }
                }
            } else {
                model.toggleOverlay()
            }
        }
    }
}

/// One continuous outline keeps the arrow attached without a seam through its base.
struct MascotTooltipBubble: InsettableShape {
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape { insetted(by: amount) }

    func insetted(by amount: CGFloat) -> MascotTooltipBubble {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func tailTip(in inputRect: CGRect) -> CGPoint {
        let rect = inputRect.insetBy(dx: insetAmount, dy: insetAmount)
        return CGPoint(x: rect.midX, y: rect.maxY)
    }

    func path(in inputRect: CGRect) -> Path {
        let rect = inputRect.insetBy(dx: insetAmount, dy: insetAmount)
        let r: CGFloat = 9
        let bottom = rect.maxY - 6
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: bottom), control: CGPoint(x: rect.maxX, y: bottom))
        path.addLine(to: CGPoint(x: rect.midX + 5, y: bottom))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - 5, y: bottom))
        path.addLine(to: CGPoint(x: rect.minX + r, y: bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: bottom - r), control: CGPoint(x: rect.minX, y: bottom))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
