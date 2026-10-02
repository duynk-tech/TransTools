import AppKit
import RealityKit
import SwiftUI
import simd

/// Review the authored USDZ independently of the old procedural prototype.
struct ReferenceMascotModelView: NSViewRepresentable {
    var yaw: Float
    @Binding var loadError: String?

    final class Coordinator {
        let pivot = Entity()
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.environment.background = .color(.clear)
        let anchor = AnchorEntity(world: .zero)
        let pivot = context.coordinator.pivot
        anchor.addChild(pivot)
        pivot.position = [0,0.95,0]
        do {
            let bundled = Bundle.main.resourceURL?.appendingPathComponent("MascotModel/TransToolsMascot.usdz")
            let url = bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                ?? URL(fileURLWithPath: "Resources/MascotModel/TransToolsMascot.usdz")
            let model = try Entity.load(contentsOf: url)
            func restoreIris(_ entity: Entity) {
                let name = entity.name.lowercased().replacingOccurrences(of: "_", with: " ")
                let label = name.contains("left eye") ? "Left" : (name.contains("right eye") ? "Right" : nil)
                if let label, var component = entity.components[ModelComponent.self] {
                    let textureURL = Bundle.main.resourceURL?.appendingPathComponent("MascotActivities/Eye\(label).png") ?? URL(fileURLWithPath: "Resources/MascotActivities/Eye\(label).png")
                    if let texture = try? TextureResource.load(contentsOf: textureURL) {
                        var material = UnlitMaterial()
                        material.color = .init(tint: .white, texture: .init(texture))
                        material.blending = .transparent(opacity: .init(floatLiteral: 1))
                        component.materials = [material]
                        entity.components.set(component)
                    }
                }
                for child in entity.children { restoreIris(child) }
            }
            restoreIris(model)
            let bounds = model.visualBounds(relativeTo: nil)
            guard bounds.extents.y.isFinite, bounds.extents.y > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let scale = 2.13 / bounds.extents.y
            model.scale = SIMD3<Float>(repeating: scale)
            model.position = -bounds.center * scale
            pivot.addChild(model)
        } catch {
            let description = error.localizedDescription
            DispatchQueue.main.async { loadError = description }
        }
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 38
        camera.look(at: [0,0.95,0], from: [0,0.97,3.25], relativeTo: nil)
        anchor.addChild(camera)
        let key = DirectionalLight(); key.light.intensity = 1800
        key.look(at: [0,0.95,0], from: [-3,4,3], relativeTo: nil);anchor.addChild(key)
        let fill = DirectionalLight();fill.light.intensity = 800
        fill.look(at: [0,0.95,0], from: [3,2,2], relativeTo: nil);anchor.addChild(fill)
        view.scene.addAnchor(anchor)
        return view
    }
    func updateNSView(_ view: ARView, context: Context) {
        context.coordinator.pivot.orientation = simd_quatf(angle: yaw, axis: [0,1,0])
    }
    static func dismantleNSView(_ view: ARView, coordinator: Coordinator) {
        view.scene.anchors.removeAll()
    }
}

struct ReferenceMascotModelPreview: View {
    @State private var angle: Double = 0
    @State private var dark = true
    @State private var loadError: String?
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Model 3D theo PNG").font(.title2.bold())
                    Text("So sánh tạo hình trước khi làm rig và animation.").foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Nền tối", isOn: $dark).toggleStyle(.switch)
            }
            HStack(spacing: 24) {
                VStack {
                    if let path = Bundle.main.path(forResource: "Mascot3D", ofType: "png"), let image = NSImage(contentsOfFile: path) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 300,height: 390)
                    }
                    Text("PNG chuẩn")
                }
                VStack {
                    ReferenceMascotModelView(yaw: Float(angle * .pi / 180), loadError: $loadError)
                        .frame(width: 310,height: 390)
                    Text("USDZ · model thật")
                }
            }
            if let loadError {
                Text("Không tải được model: \(loadError)").foregroundStyle(.red)
            }
            HStack {
                Text("Góc nhìn")
                Slider(value: $angle, in: -180...180)
                Text("\(Int(angle))°").monospacedDigit().frame(width: 48)
                Button("Chính diện") { angle = 0 }
            }
            Text("Bản dựng đầu tiên: hình dáng và vật liệu cần duyệt; chưa có rig chuyển động.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(minWidth: 750,minHeight: 560)
        .background(dark ? Color(red: 0.07, green: 0.12, blue: 0.18) : Color(red: 0.95, green: 0.97, blue: 0.99))
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}
