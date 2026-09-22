import AppKit
import SpriteKit
import ImageIO
import SpiritCore

@main @MainActor
struct HammerPoseSmoke {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func require(_ test: Bool, _ message: String) { precondition(test, message) }
        for side in [80.0, 128.0, 192.0] {
            for direction in [-1.0, 1.0] {
                for trick in HammerTrick.allCases {
                    let view = SKView(frame: CGRect(x: 0, y: 0, width: side, height: side))
                    let scene = SpiritScene(size: view.frame.size)
                    scene.tracksPointer = false
                    scene.automaticallyPlaysHammerTricks = false
                    scene.hammerRecallOffset.x = 140 * direction
                    scene.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
                    view.presentScene(scene); view.isPaused = true; scene.update(0)
                    require(scene.childNode(withName: "//hammerPoseTorso") != nil, "Authored torso poses must be loaded")
                    let hand = scene.childNode(withName: "//hammerPoseHand")!
                    let torso = scene.childNode(withName: "//hammerPoseTorso")!
                    let body = scene.childNode(withName: "//body")!
                    let trail = scene.childNode(withName: "//hammerMotionTrail")!
                    require(scene.playHammerTrick(trick), "Action must start")
                    let name = "\(trick.rawValue)-\(Int(side))-\(direction < 0 ? "left" : "right")"
                    let gif = CGImageDestinationCreateWithURL(output.appendingPathComponent(name + ".gif") as CFURL,
                        "com.compuserve.gif" as CFString, 72, nil)!
                    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                    var sawTurn = false, sawTrail = false, sawRecoil = false
                    var lastCaughtGrip: CGPoint?
                    for frame in 1...216 {
                        scene.update(Double(frame) / 60)
                        let held = scene.childNode(withName: "//heldHammer")!
                        let grip = held.parent!.convert(held.position, to: scene.childNode(withName: "stage")!)
                        if Double(frame) / 60 >= trick.catchTime {
                            if let previous = lastCaughtGrip {
                                require(hypot(grip.x - previous.x, grip.y - previous.y) < 2,
                                        "Caught hammer must fold back without a grip-position jump")
                            }
                            lastCaughtGrip = grip
                            // The original hand fades in before the authored hand disappears.
                            // Its palm must already meet the tool, not jump there at ownership change.
                            let originalHand = scene.childNode(withName: "//hammerHand")!
                            if !originalHand.isHidden && originalHand.alpha > 0.05 {
                                let palm = originalHand.convert(CGPoint(x: (0.385 - 0.90) * 312 * 0.047, y: 0),
                                                                to: scene.childNode(withName: "stage")!)
                                require(hypot(palm.x - grip.x, palm.y - grip.y) < 0.05,
                                        "Returning original palm must stay on the hammer grip")
                            }
                        }
                        sawTurn = sawTurn || torso.alpha > 0.9
                        sawTrail = sawTrail || trail.children.contains { !$0.isHidden && $0.alpha > 0 }
                        sawRecoil = sawRecoil || (Double(frame) / 60 > trick.catchTime && body.yScale < 0.97)
                        require(abs(hand.xScale) == 1 && hand.yScale == 1, "Authored arm length must never stretch")
                        if frame.isMultiple(of: 3) {
                            let preview = SKNode()
                            let backdrop = SKSpriteNode(color: scene.backgroundColor, size: CGSize(width: 480, height: 240))
                            backdrop.position = CGPoint(x: 240, y: 120); backdrop.zPosition = -100
                            preview.addChild(backdrop)
                            let stage = scene.childNode(withName: "stage")!.copy() as! SKNode
                            stage.setScale(2)
                            stage.position = CGPoint(x: direction < 0 ? 370 : 110, y: 30)
                            preview.addChild(stage)
                            let image = view.texture(from: preview)!.cgImage()
                            CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
                            if side == 192 && [12,24,42,66,84,90,99,111,132,162].contains(frame) {
                                try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                                    .write(to: output.appendingPathComponent("\(name)-\(frame).png"))
                            }
                        }
                    }
                    require(CGImageDestinationFinalize(gif), "GIF export must finish")
                    if trick == .recall { require(sawTurn, "Recall must turn the torso using authored poses") }
                    require(sawTrail && sawRecoil, "Flight needs a short trail and body catch recoil")
                    require(torso.alpha == 0 && hand.isHidden && trail.children.allSatisfy(\.isHidden), "Action must restore the original rig")
                    require(scene.playHammerTrick(trick), "Action must replay")
                    for frame in 217...280 { scene.update(Double(frame) / 60) }
                    scene.setDragging(true)
                    require(hand.isHidden && torso.alpha == 0 && trail.children.allSatisfy(\.isHidden), "Drag must clear authored poses and trails immediately")
                    scene.render(state: .idle, reduceMotion: true)
                    require(!scene.playHammerTrick(trick), "Reduce Motion prevents tricks")
                }
            }
        }
        print("PASS: authored fixed-length arm, torso turn, recoil, short flight trail, 80/128/192pt both directions, cleanup")
    }
}
