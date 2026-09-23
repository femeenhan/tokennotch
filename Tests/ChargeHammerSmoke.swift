import AppKit
import SpriteKit
import SpiritCore
import ImageIO

@main @MainActor
struct ChargeHammerSmoke {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let configurations = [80.0, 128.0, 192.0].flatMap { side in
            [false, true].map { (side, $0) }
        }
        for (side, light) in configurations {
            let output = output.appendingPathComponent(light ? "light" : "dark", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for tapping in [false, true] {
                let view = SKView(frame: CGRect(x: 0, y: 0, width: side, height: side))
                let scene = SpiritScene(size: view.frame.size)
                scene.tracksPointer = false
                scene.automaticallyPlaysHammerTricks = false
                scene.backgroundColor = NSColor(calibratedWhite: light ? 0.94 : 0.13, alpha: 1)
                view.presentScene(scene); view.isPaused = true; scene.update(0)
                if !tapping { scene.beginPress() }
                let hand = scene.childNode(withName: "//restingHammerHand")!
                let tool = scene.childNode(withName: "//heldHammer")!
                let bolt = scene.childNode(withName: "//chargeLightning")!
                let stage = scene.childNode(withName: "stage")!
                let sky = scene.childNode(withName: "//skyLightning")!
                let motes = scene.childNode(withName: "//chargeMotes")!
                let chargedEyes = scene.childNode(withName: "//chargedEyes")!
                let chargedMouth = scene.childNode(withName: "//chargedMouth")!
                var sawChargedFace = false
                var sawDescendingBolt = false
                let gif = tapping ? nil : CGImageDestinationCreateWithURL(
                    output.appendingPathComponent("charge-\(Int(side)).gif") as CFURL,
                    "com.compuserve.gif" as CFString, 160, nil)
                if let gif {
                    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary:
                        [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                }
                var sawLightning = false
                for frame in 1...900 {
                    if tapping && frame <= 150 && frame % 12 == 0 {
                        scene.beginPress(); _ = scene.endPress(registerTap: true)
                    }
                    if !tapping && frame == 330 { _ = scene.endPress(registerTap: false) }
                    scene.update(Double(frame) / 60)
                    if !tapping && frame == 300 {
                        precondition(scene.interactionCharge > 0.95, "A held charge must sustain its peak")
                        precondition(bolt.calculateAccumulatedFrame().width > 30,
                                     "Peak hammer electricity must spread beyond the old small ring")
                    }
                    if !tapping && frame == 450 {
                        precondition(scene.interactionCharge < 0.08, "Afterglow must finish about two seconds after release")
                    }
                    if !bolt.isHidden {
                        sawLightning = true
                        precondition(!sky.isHidden && !motes.isHidden, "Sky energy must accompany hammer arcs")
                        let core = sky.children[1] as! SKShapeNode
                        let target = tool.convert(CGPoint(x: 0, y: 17), to: stage)
                        let end = core.path!.currentPoint
                        if hypot(end.x - target.x, end.y - target.y) < 0.01 { sawDescendingBolt = true }
                        precondition(core.path!.boundingBoxOfPath.maxY > target.y + 6,
                                     "Lightning must descend from above the hammer")
                        if !chargedEyes.isHidden && !chargedMouth.isHidden { sawChargedFace = true }
                        precondition(abs(hand.xScale) == 1 && hand.yScale == 1)
                        let palm = hand.convert(CGPoint(x: 9, y: 2), to: stage)
                        let grip = tool.convert(.zero, to: stage)
                        precondition(hypot(palm.x - grip.x, palm.y - grip.y) < 0.01, "Charge hand must stay on the handle")
                    }
                    if let gif, frame <= 480, frame % 3 == 0 {
                        let image = view.texture(from: scene, crop: view.bounds)!.cgImage()
                        CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary:
                            [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
                    }
                    if !tapping && [20, 70, 110, 150, 200, 300, 360, 450, 900].contains(frame) {
                        let image = view.texture(from: scene, crop: view.bounds)!.cgImage()
                        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                            .write(to: output.appendingPathComponent("charge-\(Int(side))-\(frame).png"))
                    }
                }
                if let gif { precondition(CGImageDestinationFinalize(gif)) }
                precondition(sawDescendingBolt, "Sky bolt must reach the rotating hammer head")
                precondition(sawChargedFace, "Full charge must show braced mouth and lit eyes")
                precondition(sky.isHidden && motes.isHidden && chargedEyes.isHidden && chargedMouth.isHidden,
                             "Charge-only effects and face must clear after decay")
                precondition(sawLightning, "Both hold and repeated taps must charge the hammer")
                precondition(bolt.isHidden, "Electricity must clear after charge decays")
                scene.beginPress()
                for frame in 901...1050 { scene.update(Double(frame) / 60) }
                precondition(!sky.isHidden, "Recharging must restore sky lightning")
                scene.render(state: .idle, reduceMotion: true)
                precondition(sky.isHidden && motes.isHidden, "Reduced motion must clear active sky effects")
                precondition(bolt.isHidden, "Reduced motion must suppress lightning")
            }
        }
        print("PASS: hold/tap charged grip, rigid arm, descending sky lightning, charging face, electricity decay and active reduced motion at 80/128/192pt on light/dark backgrounds")
    }
}
