import AppKit
import SpriteKit
import ImageIO
import SpiritCore

/// Exercises the production input wrappers and renderer at actual companion sizes.
@main
@MainActor
struct EmotionSceneSmoke {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func require(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
        for side in [128.0, 192.0] {
            let view = SKView(frame: CGRect(x: 0, y: 0, width: side, height: side))
            view.allowsTransparency = true
            for scenario in ["petting", "drag-release", "completion", "reduced-motion", "typing"] {
                let scene = SpiritScene(size: view.frame.size)
                scene.tracksPointer = false
                scene.automaticallyPlaysHammerTricks = false
                scene.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1)
                view.presentScene(scene)
                view.isPaused = true
                require(scene.assetLoaded, "Actual sprite atlas must load")
                scene.update(0)
                let body = scene.childNode(withName: "//body")!
                if scenario == "completion" { scene.render(state: .completed, reduceMotion: false) }
                if scenario == "reduced-motion" { scene.render(state: .completed, reduceMotion: true) }
                if scenario == "petting" {
                    require(scene.playHammerTrick(.toss), "Idle tool action must start")
                }
                if scenario == "drag-release" { scene.setDragging(true) }
                let name = "\(scenario)-\(Int(side))"
                let gif = CGImageDestinationCreateWithURL(output.appendingPathComponent(name + ".gif") as CFURL,
                    "com.compuserve.gif" as CFString, 80, nil)!
                CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary:
                    [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                var sawExpression = false
                var sawStretch = false
                var releasedScale: CGFloat = 1
                var reducedStart: (CGPoint, CGFloat, CGFloat, CGFloat)?
                for frame in 1...240 {
                    if scenario == "petting", frame <= 80 {
                        scene.setPointer(x: sin(Double(frame) / 12) * 12, y: 44, velocityX: 40, velocityY: 0)
                    }
                    if scenario == "petting", frame == 81 { scene.setPointer(x: nil, y: nil) }
                    if scenario == "drag-release" {
                        if frame < 65 { scene.setDragVelocity(x: 180, y: 75) }
                        if frame == 65 { scene.setDragging(false); scene.setDragVelocity(x: 0, y: 0) }
                    }
                    if scenario == "typing" { scene.setTypingActive(frame <= 150) }
                    scene.update(Double(frame) / 60)
                    if scenario == "typing", frame == 90 {
                        require(scene.displayedExpression == .focused, "Typing must display focused eyes")
                        require(!scene.isHammerTrickPlaying, "Typing must not toss the hammer")
                    }
                    if scenario == "typing", frame == 240 {
                        require(scene.displayedExpression != .focused, "Typing focus must settle after input stops")
                    }
                    if scenario == "petting" {
                        sawExpression = sawExpression || scene.displayedExpression == .content
                        require(!scene.isHammerTrickPlaying, "Petting must reclaim the hammer")
                        if scene.displayedExpression == .content {
                            require(scene.childNode(withName: "//happyEyes")?.isHidden == false,
                                    "Contentment must show happy arches")
                            require(scene.childNode(withName: "//closedEyes")?.isHidden == true,
                                    "Happy eyes must differ from sleepy lids")
                            require(scene.childNode(withName: "//smileMouth")?.isHidden == false,
                                    "Contentment must show a smile")
                        }
                    }
                    if scenario == "completion" {
                        sawExpression = sawExpression || scene.displayedExpression == .proud
                    }
                    if scenario == "drag-release" {
                        if frame < 65 { sawStretch = sawStretch || body.yScale > 1.06 }
                        if frame == 240 { releasedScale = body.yScale }
                    }
                    if scenario == "reduced-motion" {
                        let current = (body.position, body.xScale, body.yScale, body.zRotation)
                        if let first = reducedStart {
                            require(first.0 == current.0 && first.1 == current.1 && first.2 == current.2 && first.3 == current.3,
                                    "Reduce Motion must keep the body still")
                        } else { reducedStart = current }
                        require(scene.displayedExpression == .proud, "Reduce Motion must retain the completion expression")
                    }
                    if frame.isMultiple(of: 3) {
                        guard let texture = view.texture(from: scene, crop: view.bounds) else { fatalError("Capture failed") }
                        let image = texture.cgImage()
                        if scenario == "drag-release" {
                            let bitmap = NSBitmapImageRep(cgImage: image)
                            let clippedFlamePixels = (0..<bitmap.pixelsWide).filter { x in
                                guard let c = bitmap.colorAt(x: x, y: 0)?.usingColorSpace(.deviceRGB) else { return false }
                                return c.redComponent > 0.7 && c.greenComponent > 0.1 && c.blueComponent < 0.6
                            }.count
                            if clippedFlamePixels >= 5 {
                                let png = bitmap.representation(using: .png, properties: [:])!
                                try png.write(to: output.appendingPathComponent("clipped-\(Int(side))-\(frame).png"))
                            }
                            require(clippedFlamePixels < 5, "The stretched flame must fit below the window's top edge (\(side)pt, frame \(frame), \(clippedFlamePixels) pixels)")
                        }
                        CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary:
                            [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
                        if [30, 60, 90, 150, 240].contains(frame) {
                            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                            try png.write(to: output.appendingPathComponent("\(name)-\(frame).png"))
                        }
                    }
                }
                require(CGImageDestinationFinalize(gif), "GIF must export")
                if scenario == "petting" || scenario == "completion" { require(sawExpression, "\(scenario) expression must be visible") }
                if scenario == "drag-release" {
                    require(sawStretch, "Dragging must deform the whole body")
                    require(abs(releasedScale - 1) < 0.04, "Released body must settle")
                }
            }
        }
        print("PASS: real renderer petting, drag/release, proud completion, Reduce Motion; 128/192pt PNG and GIF: \(output.path)")
    }
}
