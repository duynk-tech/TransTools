import SwiftUI
import AppKit

/// Listen only while the orbit is open. Never consume the click meant for another app.
struct MascotOutsideClickMonitor: NSViewRepresentable {
    let expanded: Bool
    let dismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(view: view, expanded: expanded, dismiss: dismiss)
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator {
        private var local: Any?
        private var global: Any?
        private weak var view: NSView?
        private var dismiss: (() -> Void)?

        func update(view: NSView, expanded: Bool, dismiss: @escaping () -> Void) {
            self.view = view
            self.dismiss = dismiss
            guard expanded else { stop(); return }
            guard local == nil else { return }
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self, let window = self.view?.window else { return event }
                let clickedInsideWheel: Bool
                if event.window === window, let view = self.view {
                    let point = view.convert(event.locationInWindow, from: nil)
                    clickedInsideWheel = MascotOutsideClickPolicy.contains(point, in: view.bounds)
                } else {
                    clickedInsideWheel = false
                }
                if !clickedInsideWheel {
                    self.scheduleDismiss()
                }
                return event
            }
            global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                DispatchQueue.main.async { self?.scheduleDismiss() }
            }
        }
        private func scheduleDismiss() {
            let action = dismiss
            stop()
            DispatchQueue.main.async { action?() }
        }
        func stop() {
            if let local { NSEvent.removeMonitor(local) }
            if let global { NSEvent.removeMonitor(global) }
            local = nil; global = nil
        }
        deinit { stop() }
    }
}

enum MascotOutsideClickPolicy {
    /// Covers the 122 pt icon orbit, 24 pt icon radius, and tooltip above the
    /// top icon while excluding the transparent corners of the launcher panel.
    static let activeRadius: CGFloat = 162

    static func contains(_ point: CGPoint, in bounds: CGRect, radius: CGFloat = activeRadius) -> Bool {
        guard !bounds.isNull, !bounds.isEmpty, radius >= 0 else { return false }
        return hypot(point.x - bounds.midX, point.y - bounds.midY) <= radius
    }
}
