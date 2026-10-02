import AppKit
import Combine
import RealityKit
import SwiftUI
import simd

/// Procedural prototype: genuine geometry and joints, no sprite interpolation.
struct RealtimeMascotView: NSViewRepresentable {
    var walking = false
    var towardRight = true
    var distance: CGFloat? = nil
    var facing: MascotFacing? = nil
    var working = false
    var sleeping = false
    var expression: MascotExpression? = nil
    var reduceMotion = false
    var activity = "auto"

    func makeCoordinator() -> Rig { Rig() }
    func makeNSView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.environment.background = .color(.clear)
        context.coordinator.install(in: view)
        context.coordinator.input = self
        return view
    }
    func updateNSView(_ view: ARView, context: Context) {
        context.coordinator.input = self
    }
    static func dismantleNSView(_ view: ARView, coordinator: Rig) {
        coordinator.subscription?.cancel()
        coordinator.subscription = nil
        view.scene.anchors.removeAll()
    }

    @MainActor final class Rig {
        var input = RealtimeMascotView()
        var subscription: Cancellable?
        let root = Entity()
        let torso = Entity()
        let head = Entity()
        let coffee = Entity()
        let notebook = Entity()
        let pencil = Entity()
        let flower = Entity()
        let butterfly = Entity()
        let pillow = Entity()
        var eyes: [Entity] = []
        var arms: [Entity] = []
        var thighs: [ModelEntity] = []
        var shins: [ModelEntity] = []
        var feet: [Entity] = []
        var clock: Double = 0
        var yaw: Float = 0
        var phase: Float = 0
        var gaitWeight: Float = 0

        let pearl = SimpleMaterial(color: NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.97, alpha: 1), roughness: 0.32, isMetallic: false)
        let mint = SimpleMaterial(color: NSColor(calibratedRed: 0.28, green: 0.84, blue: 0.81, alpha: 1), roughness: 0.27, isMetallic: false)
        let dark = SimpleMaterial(color: NSColor(calibratedRed: 0.015, green: 0.05, blue: 0.09, alpha: 1), roughness: 0.22, isMetallic: false)
        let panel = SimpleMaterial(color: NSColor(calibratedRed: 0.76, green: 0.82, blue: 0.89, alpha: 1), roughness: 0.45, isMetallic: false)

        @discardableResult
        func oval(_ parent: Entity, _ position: SIMD3<Float>, _ scale: SIMD3<Float>, _ material: SimpleMaterial) -> ModelEntity {
            let entity = ModelEntity(mesh: .generateSphere(radius: 1), materials: [material])
            entity.position = position
            entity.scale = scale
            parent.addChild(entity)
            return entity
        }
        func install(in view: ARView) {
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(root)
            root.addChild(torso)
            torso.addChild(head)
            oval(torso, [0,0.60,0], [0.25,0.30,0.19], pearl)
            oval(torso, [0,0.90,0], [0.11,0.10,0.11], panel)
            head.position = [0,1.27,0]
            oval(head, .zero, [0.54,0.39,0.30], pearl)
            oval(head, [0,0,0.20], [0.455,0.305,0.125], panel)
            oval(head, [0,0,0.235], [0.438,0.29,0.098], pearl)
            for side: Float in [-1,1] {
                let eye = Entity(); eye.position = [side*0.18,0.015,0.36]; head.addChild(eye)
                let name = side < 0 ? "EyeLeft" : "EyeRight"
                let url = Bundle.main.resourceURL?.appendingPathComponent("MascotActivities/\(name).png") ?? URL(fileURLWithPath: "Resources/MascotActivities/\(name).png")
                if let texture = try? TextureResource.load(contentsOf: url) {
                    var material = UnlitMaterial()
                    material.color = .init(tint: .white, texture: .init(texture))
                    material.blending = .transparent(opacity: .init(floatLiteral: 1))
                    let surface = ModelEntity(mesh: .generatePlane(width: 0.225, depth: 0.23), materials: [material])
                    surface.orientation = simd_quatf(angle: .pi/2, axis: [1,0,0])
                    eye.addChild(surface)
                } else {
                    oval(eye, .zero, [0.105,0.11,0.015], dark)
                    oval(eye, [-0.025,0.04,0.016], [0.025,0.026,0.008], pearl)
                }
                eyes.append(eye)
                oval(head, [side*0.53,0.015,0], [0.085,0.24,0.20], panel)
                oval(head, [side*0.59,0.015,0], [0.04,0.22,0.18], pearl)
                oval(head, [side*0.625,0.015,0], [0.012,0.16,0.135], mint)
                let arm = Entity();arm.position = [side*0.25,0.74,0];torso.addChild(arm)
                oval(arm, [side*0.07,-0.12,0.02], [0.10,0.17,0.10], pearl)
                oval(arm, [side*0.09,-0.23,0.045], [0.105,0.10,0.11], pearl)
                arms.append(arm)
                thighs.append(oval(root, .zero, [0.09,0.12,0.09], pearl))
                shins.append(oval(root, .zero, [0.08,0.12,0.08], pearl))
                let foot = Entity(); root.addChild(foot)
                oval(foot, [0,0,-0.025], [0.085,0.06,0.08], pearl) // heel
                oval(foot, [0,-0.005,0.085], [0.10,0.055,0.12], pearl) // toe faces +Z
                feet.append(foot)
            }
            // A single smooth mesh avoids bead-like seams along the band.
            var vertices: [SIMD3<Float>] = []
            var normals: [SIMD3<Float>] = []
            var indices: [UInt32] = []
            let rings = 64, sides = 20
            for ring in 0...rings {
                let angle = Float(ring)/Float(rings) * .pi
                let center = SIMD3<Float>(cos(angle)*0.57,sin(angle)*0.49+0.055,-0.025)
                let outward = simd_normalize(SIMD3<Float>(cos(angle)/0.57,sin(angle)/0.49,0))
                for side in 0..<sides {
                    let a = Float(side)/Float(sides) * 2 * .pi
                    vertices.append(center + outward*cos(a)*0.035 + SIMD3<Float>(0,0,sin(a)*0.085))
                    normals.append(simd_normalize(outward*cos(a)/0.035 + SIMD3<Float>(0,0,sin(a)/0.085)))
                    if ring < rings {
                        let current = UInt32(ring*sides+side)
                        let next = UInt32(ring*sides+(side+1)%sides)
                        let below = current+UInt32(sides)
                        let belowNext = next+UInt32(sides)
                        indices += [current,below,next,next,below,belowNext]
                    }
                }
            }
            var descriptor = MeshDescriptor(name: "Smooth headphone band")
            descriptor.positions = MeshBuffers.Positions(vertices)
            descriptor.normals = MeshBuffers.Normals(normals)
            descriptor.primitives = .triangles(indices)
            if let mesh = try? MeshResource.generate(from: [descriptor]) {
                head.addChild(ModelEntity(mesh: mesh, materials: [pearl]))
            }
            torso.addChild(coffee); coffee.position = [-0.03,0.64,0.34]
            oval(coffee, .zero, [0.095,0.10,0.085], pearl)
            let brown = SimpleMaterial(color: .brown, roughness: 0.8, isMetallic: false)
            oval(coffee, [0,0.09,0], [0.08,0.008,0.07], brown)
            for i in 0..<16 {
                let a = Float(i)/16 * 2 * .pi
                oval(coffee, [0.10+cos(a)*0.045,sin(a)*0.065,0], [0.016,0.016,0.018], pearl)
            }
            torso.addChild(notebook); notebook.position = [-0.04,0.64,0.32]
            let cover = ModelEntity(mesh: .generateBox(size: [0.29,0.33,0.035], cornerRadius: 0.012), materials: [mint]); notebook.addChild(cover)
            let pages = ModelEntity(mesh: .generateBox(size: [0.25,0.29,0.012], cornerRadius: 0.005), materials: [pearl]); pages.position.z = 0.025; notebook.addChild(pages)
            for row in 0..<5 {
                let line = ModelEntity(mesh: .generateBox(size: [0.18,0.004,0.002]), materials: [panel]); line.position = [0,Float(row)*0.035-0.07,0.033]; notebook.addChild(line)
            }
            arms[1].addChild(pencil); pencil.position = [0.09,-0.23,0.06]
            oval(pencil, .zero, [0.014,0.16,0.014], mint)
            oval(pencil, [0,-0.16,0], [0.012,0.025,0.012], dark)
            arms[1].addChild(flower); flower.position = [0.09,-0.23,0.09]
            oval(flower, [0,0.09,0], [0.012,0.14,0.012], mint)
            for i in 0..<7 {
                let a = Float(i)/7 * 2 * .pi
                oval(flower, [cos(a)*0.055,0.22+sin(a)*0.055,0], [0.037,0.045,0.018], pearl)
            }
            oval(flower, [0,0.22,0.02], [0.026,0.026,0.018], brown)
            anchor.addChild(butterfly)
            for side: Float in [-1,1] { oval(butterfly, [side*0.055,0,0], [0.065,0.09,0.013], mint) }
            oval(butterfly, .zero, [0.015,0.06,0.015], dark)
            anchor.addChild(pillow); pillow.position = [-0.03,0.16,0]
            oval(pillow, .zero, [0.56,0.09,0.27], pearl)
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 38
            camera.look(at: [0,0.96,0], from: [0,1.08,3.3], relativeTo: nil)
            anchor.addChild(camera)
            let key = DirectionalLight(); key.light.intensity = 2200
            key.look(at: [0,0.8,0], from: [-2,3,3], relativeTo: nil); anchor.addChild(key)
            let fill = DirectionalLight(); fill.light.intensity = 900
            fill.look(at: [0,1,0], from: [2,1.5,2], relativeTo: nil); anchor.addChild(fill)
            view.scene.addAnchor(anchor)
            subscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                self?.tick(Float(event.deltaTime))
            }
        }
        func bone(_ entity: ModelEntity, from a: SIMD3<Float>, to b: SIMD3<Float>, width: Float) {
            let delta = b-a
            entity.position = (a+b)*0.5
            entity.scale = [width,simd_length(delta)*0.58,width]
            entity.orientation = simd_quatf(from: [0,1,0], to: simd_normalize(delta))
        }
        func tick(_ elapsed: Float) {
            let dt = min(elapsed,0.05)
            clock += Double(dt)
            let sleeping = input.sleeping || input.activity == "sleeping"
            let writing = input.working || input.activity == "writing"
            let thinking = input.activity == "thinking"
            let drinking = input.activity == "tea"
            let picking = input.activity == "flowers"
            let catching = input.activity == "butterfly"
            coffee.isEnabled = drinking && !sleeping
            notebook.isEnabled = writing && !sleeping
            pencil.isEnabled = writing && !sleeping
            flower.isEnabled = picking && !sleeping
            butterfly.isEnabled = catching && !sleeping
            pillow.isEnabled = sleeping
            let desired: Float
            if input.walking { desired = input.towardRight ? .pi/2 : -.pi/2 }
            else {
                switch input.facing ?? .front {
                case .front: desired = 0
                case .frontRight: desired = .pi/4
                case .right: desired = .pi/2
                case .backRight: desired = .pi*0.75
                case .back: desired = .pi
                case .backLeft: desired = -.pi*0.75
                case .left: desired = -.pi/2
                case .frontLeft: desired = -.pi/4
                }
            }
            let difference = atan2(sin(desired-yaw),cos(desired-yaw))
            yaw += difference * (input.reduceMotion ? 1 : 1-exp(-dt*10))
            root.orientation = sleeping ? simd_quatf(angle: 1.2, axis: [0,0,1]) : simd_quatf(angle: yaw, axis: [0,1,0])
            root.scale = sleeping ? SIMD3<Float>(repeating: 0.68) : SIMD3<Float>(repeating: 1)
            root.position = sleeping ? [0.55,0.30,0] : .zero
            gaitWeight += ((input.walking && !input.reduceMotion ? 1 : 0)-gaitWeight)*(1-exp(-dt*12))
            if input.walking && !input.reduceMotion {
                if let distance = input.distance { phase = Float(distance/26) * 2 * .pi }
                else { phase += dt * 2 * .pi * 1.25 }
            }
            let bob: Float = input.reduceMotion ? 0 : 0.009*sin(Float(clock)*2.2) + gaitWeight*0.012*cos(phase*2)
            torso.position.y = bob
            head.orientation = simd_quatf(angle: sleeping ? -0.14 : (writing ? -0.16 : (thinking ? 0.10 : (picking ? -0.22 : 0))), axis: [1,0,0])
            butterfly.position = [0.42+0.12*sin(Float(clock)*1.6),1.15+0.12*cos(Float(clock)*1.2),0.35]
            butterfly.scale.x = input.reduceMotion ? 1 : 0.5+0.5*abs(sin(Float(clock)*9))
            let blink = Float(clock.truncatingRemainder(dividingBy: 4.6))
            for i in 0..<2 {
                let wink = (i == 0 && input.expression == .winkLeft) || (i == 1 && input.expression == .winkRight)
                eyes[i].scale.y = sleeping || wink ? 0.10 : ((!input.reduceMotion && blink < 0.14) ? 0.15 : 1)
                let side: Float = i == 0 ? -1 : 1
                let p = phase + (i == 0 ? 0 : .pi)
                let swing = -sin(p)*0.30*gaitWeight
                let reach: Float = sleeping ? -0.9 : writing ? (i == 0 ? -1.15 : -1.0 + (input.reduceMotion ? 0 : 0.10*sin(Float(clock)*5))) : (drinking ? -1.3 : ((picking || catching) && i == 1 ? -1.5 : swing))
                arms[i].orientation = simd_quatf(angle: reach, axis: [1,0,0]) * simd_quatf(angle: thinking && i == 1 ? -2.25 : ((drinking || writing) ? side * -0.8 : 0), axis: [0,0,1])
                arms[i].position = [side*0.25,thinking && i == 1 ? 0.94 : 0.74,thinking && i == 1 ? 0.16 : 0]
                let hip = SIMD3<Float>(side*0.135,0.43+bob,0)
                let ankle = sleeping ? SIMD3<Float>(side*0.10,0.25,0.16) : SIMD3<Float>(side*0.135,0.075+max(0,sin(p))*0.09*gaitWeight,-cos(p)*0.13*gaitWeight)
                // Two-link leg: solve the knee from hip/ankle distance. The
                // stance foot stays on the ground while the pelvis breathes.
                let vector = ankle-hip
                let length = simd_length(vector)
                let bend = sqrt(max(0,0.225*0.225-length*length/4))
                let forward = simd_normalize(SIMD3<Float>(0,-vector.z,vector.y))
                let knee = (hip+ankle)/2 - forward*bend
                bone(thighs[i],from:hip,to:knee,width:0.09)
                bone(shins[i],from:knee,to:ankle,width:0.08)
                feet[i].position = ankle
                feet[i].orientation = simd_quatf(angle: max(0,sin(p))*0.12*gaitWeight, axis: [1,0,0])
            }
        }
    }
}
