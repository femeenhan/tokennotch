import AppKit
import SpriteKit
import SpiritCore

@main @MainActor
struct GroundedHammerSmoke {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func require(_ value: Bool, _ message: String) { precondition(value, message) }
        for side in [80.0, 128.0, 192.0] {
            let view = SKView(frame: CGRect(x: 0, y: 0, width: side, height: side))
            let scene = SpiritScene(size: view.frame.size)
            scene.tracksPointer = false
            scene.automaticallyPlaysHammerTricks = false
            scene.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1)
            view.presentScene(scene); view.isPaused = true; scene.update(0)
            let stage = scene.childNode(withName: "stage")!
            let held = scene.childNode(withName: "//heldHammer") as! SKSpriteNode
            let hand = scene.childNode(withName: "//restingHammerHand")!
            func grip() -> CGPoint { held.convert(.zero, to: stage) }
            let restingGrip = grip()
            require(abs(held.parent!.zRotation - .pi) < 0.001, "Resting hammer head must lie flat, not balance on a corner")
            let body = scene.childNode(withName: "//body")!
            let folded = scene.childNode(withName: "//foldedFreeHand")!
            require(!hand.isHidden, "Idle must show the short resting hand")
            require(scene.hammerContains(held.convert(.zero, to: scene)), "Resting hammer must remain interactive")
            var time = 0.0
            for frame in 1...300 {
                if frame == 60 { scene.setTypingActive(true) }
                if frame == 150 {
                    scene.setTypingActive(false); scene.render(state: .working, reduceMotion: false)
                }
                if frame == 240 { scene.render(state: .idle, reduceMotion: false) }
                time += 1.0 / 60
                scene.update(time)
                if frame == 155 {
                    require(abs(held.parent!.zRotation - .pi) < 0.001,
                            "Hammer must remain grounded during the initial posture correction")
                    require(folded.alpha < 1,
                            "Arms must unfold before lifting the handle")
                }
                if frame < 150 {
                    require(hypot(grip().x - restingGrip.x, grip().y - restingGrip.y) < 0.001,
                            "Resting hammer must remain planted during breathing and typing")
                    let palm = hand.convert(CGPoint(x: 9, y: 2), to: body)
                    require(abs(palm.x) < 4 && palm.y < 16 && palm.y > 6,
                            "Resting hands must remain across the belly, away from the face")
                    require(!folded.isHidden, "Idle must show both folded forearms")
                    require(abs(hand.xScale) == 1 && hand.yScale == 1, "Resting arm must never stretch")
                }
                if [30, 120, 155, 162, 175, 210, 300].contains(frame) {
                    let image = view.texture(from: scene, crop: view.bounds)!.cgImage()
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("rest-\(Int(side))-\(frame).png"))
                }
            }
            scene.render(state: .idle, reduceMotion: true)
            require(!hand.isHidden, "Reduced motion idle must retain the grounded pose")
        }
        print("PASS: planted hammer and rigid grip during idle/typing, pickup, work, reduced motion at 80/128/192pt")
    }
}
