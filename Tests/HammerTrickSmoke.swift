import AppKit
import SpriteKit
import ImageIO
import SpiritCore

@main
@MainActor
struct HammerTrickSmoke {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 192, height: 192))
        view.allowsTransparency = true
        func require(_ value: Bool, _ message: String) {
            if !value { fatalError(message) }
        }
        func makeScene() -> SpiritScene {
            let scene = SpiritScene(size: view.frame.size)
            scene.tracksPointer = false
            scene.automaticallyPlaysHammerTricks = false
            scene.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1)
            scene.provider = .codex
            view.presentScene(scene)
            view.isPaused = true
            scene.update(0)
            return scene
        }
        for trick in HammerTrick.allCases {
            let scene = makeScene()
            let held = scene.childNode(withName: "//heldHammer") as! SKSpriteNode
            let flying = scene.childNode(withName: "//flyingHammer") as! SKSpriteNode
            let hand = scene.childNode(withName: "//hammerHand")!
            require(scene.playHammerTrick(trick), "Idle scene must accept \(trick)")
            require(!scene.playHammerTrick(trick), "Repeated requests must not duplicate a flying hammer")
            let gif = CGImageDestinationCreateWithURL(output.appendingPathComponent("hammer-\(trick.rawValue).gif") as CFURL,
                                                      "com.compuserve.gif" as CFString, 60, nil)!
            CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            var sawDetached = false
            var sawDistant = false
            for frame in 1...180 {
                scene.update(Double(frame) / 60)
                if !flying.isHidden {
                    sawDetached = true
                    require(held.isHidden && (!hand.isHidden || scene.childNode(withName: "//hammerPoseHand")?.isHidden == false), "Only the tool must leave the visible hand")
                    let grip = held.parent!.convert(held.position, to: flying.parent!)
                    sawDistant = sawDistant || abs(flying.position.x - grip.x) > 100
                }
                if frame.isMultiple(of: 3) {
                    // Compose a wider stage without stretching SKScene's viewport projection.
                    let width: CGFloat = trick == .recall ? 510 : 240
                    let preview = SKNode()
                    let backdrop = SKSpriteNode(color: scene.backgroundColor, size: CGSize(width: width, height: 280))
                    backdrop.position = CGPoint(x: width / 2, y: 140)
                    backdrop.zPosition = -100
                    preview.addChild(backdrop)
                    let stage = scene.childNode(withName: "stage")!.copy() as! SKNode
                    stage.setScale(2.5)
                    stage.position = CGPoint(x: 100, y: 35)
                    preview.addChild(stage)
                    let image = view.texture(from: preview)!.cgImage()
                    CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary:
                        [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
                    if [18, 42, 66, 90, 111].contains(frame) {
                        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                        try png.write(to: output.appendingPathComponent("\(trick.rawValue)-\(frame).png"))
                    }
                }
            }
            require(CGImageDestinationFinalize(gif), "Animation preview must export")
            require(sawDetached && (trick != .recall || sawDistant), "Both flight paths must be visible and distinct")
            require(!scene.isHammerTrickPlaying && !held.isHidden && flying.isHidden,
                    "The trick must end with exactly one held hammer")
            require(held.alpha == 1, "Recall must restore a fully opaque held tool")

            var externalFrame: HammerFlightFrame?
            scene.onHammerFlight = { externalFrame = $0 }
            require(scene.playHammerTrick(trick), "A finished trick must be replayable")
            for frame in 181...225 { scene.update(Double(frame) / 60) }
            require(externalFrame != nil && flying.isHidden && held.isHidden,
                    "External flight must replace both in-window copies")
            scene.render(state: .working, reduceMotion: false)
            require(externalFrame == nil && !held.isHidden && !scene.isHammerTrickPlaying,
                    "Real work must reclaim the hammer and clear the external flight")
            scene.render(state: .idle, reduceMotion: false)
            require(!scene.playHammerTrick(trick), "A recovering forge stroke must keep ownership of the hammer")
            // Include the new .55s preparation before the final strike recovers.
            for frame in 226...360 { scene.update(Double(frame) / 60) }
            require(scene.playHammerTrick(trick), "A recovered idle hammer must allow a new trick")
            scene.beginPress()
            require(!scene.isHammerTrickPlaying && !held.isHidden, "Pressing must safely reclaim the tool")
            _ = scene.endPress(registerTap: false)
            require(scene.playHammerTrick(trick), "Cancelled trick must be replayable")
            scene.render(state: .idle, reduceMotion: true)
            require(!scene.isHammerTrickPlaying && !held.isHidden && externalFrame == nil,
                    "Reduce Motion must immediately restore attachment")
            require(!scene.playHammerTrick(trick), "Reduce Motion must prevent new flight")
        }
        let automatic = makeScene()
        automatic.automaticallyPlaysHammerTricks = true
        var sawAutomatic = false
        for frame in 1...5400 {
            // One idle scheduler now starts with an ember episode. Brief engagement
            // resets sleep so the next scheduled action can be the hammer toss.
            if frame == 2400 { automatic.setPointer(x: 30, y: 35) }
            if frame == 2401 { automatic.setPointer(x: nil, y: nil) }
            automatic.update(Double(frame) / 60)
            sawAutomatic = sawAutomatic || automatic.isHammerTrickPlaying
        }
        require(sawAutomatic, "A healthy idle companion should occasionally toss its hammer")
        print("PASS: toss, recall, independent hand, attachment, external handoff, cancellation, idle trigger; \(output.path)")
    }
}
