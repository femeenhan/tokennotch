import AppKit
import SpriteKit
import ImageIO
import SpiritCore

/// Compile alongside SpiritScene.swift; exercises the real renderer, not a mock.
@main
@MainActor
struct RigSceneSmoke {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let scene = SpiritScene(size: CGSize(width: 384, height: 384))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 384, height: 384))
        view.allowsTransparency = true
        view.presentScene(scene)
        scene.tracksPointer = false
        view.isPaused = true
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        func require(_ condition: Bool, _ message: String) {
            if !condition { fatalError(message) }
        }
        require(scene.assetLoaded, "Rig atlas failed to load")
        require(NSFont(name: "NeoDunggeunmo-Regular", size: 16) != nil, "Bundled pixel font must load")
        scene.provider = .codex
        scene.isObserved = false
        var hasQuestionBadge = false
        scene.enumerateChildNodes(withName: "//*") { node, _ in
            if let label = node as? SKLabelNode, label.text == "?", !label.isHidden {
                hasQuestionBadge = true
            }
        }
        require(!hasQuestionBadge, "Unobserved providers must not display a question-mark badge")
        require(!scene.displayedLabel.contains("?"), "Unobserved identity must not add a question mark")
        scene.isObserved = true
        for side in [80.0, 128.0, 192.0, 384.0] {
            scene.size = CGSize(width: side, height: side)
            let label = scene.childNode(withName: "providerLabel") as! SKSpriteNode
            let stage = scene.childNode(withName: "stage")!
            require(abs(label.frame.midX - stage.position.x) < 0.01, "Nameplate must align with character at every size")
            require(label.texture?.filteringMode == .nearest, "Pixel label must retain sharp edges")
        }
        scene.size = CGSize(width: 384, height: 384)
        let hammer = scene.childNode(withName: "//hammer")
        let head = scene.childNode(withName: "//head")
        let eyes = scene.childNode(withName: "//eyes")
        let body = scene.childNode(withName: "//body")!
        require(hammer != nil && head != nil && eyes != nil,
                "Head, eyes and hammer must be independent rig nodes, not one rocking PNG")
        scene.render(state: .working, reduceMotion: false)
        var angles: [CGFloat] = []
        var sawSparks = false
        var captured = 0
        var sawShapedFlame = false
        var time = 0.0
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for frame in 0...100 {
            time = Double(frame) / 60
            scene.update(time)
            require(body.alpha == 1, "Working spirit body must remain fully opaque")
            angles.append(hammer!.zRotation)
            sawSparks = sawSparks || !(scene.childNode(withName: "//sparks")?.children.isEmpty ?? true)
            if let flame = scene.childNode(withName: "//flyingFlame") as? SKSpriteNode {
                sawShapedFlame = sawShapedFlame || (flame.texture != nil
                    && flame.size.height > flame.size.width
                    && flame.childNode(withName: "flameTail") != nil)
            }
            if [0, 24, 35, 39, 60, 90].contains(frame) {
                guard let texture = view.texture(from: scene, crop: view.bounds),
                      let data = NSBitmapImageRep(cgImage: texture.cgImage()).representation(using: .png, properties: [:])
                else { fatalError("Frame \(frame) could not be captured") }
                try data.write(to: output.appendingPathComponent("forge-\(frame).png"))
                captured += 1
            }
        }
        require(captured == 6, "All six rendered snapshots must be written")
        require(sawShapedFlame, "Flying embers must have a layered flame texture and tail")
        require(sawSparks, "Actual rendered sparks must appear during a strike")
        require((angles.max()! - angles.min()!) > 1, "Hammer must swing independently through a visible arc")
        scene.render(state: .idle, reduceMotion: false)
        for _ in 0..<180 { time += 1.0 / 60; scene.update(time) }
        require(abs(hammer!.zRotation) < 0.15, "Hammer must settle after returning to idle")
        let core = scene.childNode(withName: "//coreGlow") as! SKSpriteNode
        let normalScale = core.yScale
        scene.remainingQuota = 0.05
        for _ in 0..<240 { time += 1.0 / 60; scene.update(time) }
        require(core.yScale < normalScale - 0.2, "Low quota must visibly reduce the core")
        for (name, state, quota) in [("tired", SpiritState.idle, 0.05),
                                     ("attention", .attention, 0.05), ("sleep", .sleeping, 0.05),
                                     ("recovery", .idle, 1.0), ("celebrate", .completed, 1.0)] {
            scene.remainingQuota = quota
            scene.render(state: state, reduceMotion: false)
            for _ in 0..<30 { time += 1.0 / 60; scene.update(time) }
            require(body.alpha == 1, "Quota and rest states must preserve body opacity")
            require(eyes!.yScale == 1, "Dedicated eye expressions must preserve the eye node height")
            if state == .attention {
                require((scene.childNode(withName: "//heldEmber")?.alpha ?? 0) > 0.5,
                        "Attention must offer a held ember")
            }
            guard let texture = view.texture(from: scene, crop: view.bounds),
                  let data = NSBitmapImageRep(cgImage: texture.cgImage()).representation(using: .png, properties: [:])
            else { fatalError("Expanded motion snapshot failed") }
            try data.write(to: output.appendingPathComponent("\(name).png"))
        }
        scene.render(state: .working, reduceMotion: true)
        time += 1.0 / 60; scene.update(time)
        let still = hammer!.zRotation
        for _ in 0..<120 { time += 1.0 / 60; scene.update(time) }
        require(hammer!.zRotation == still, "Reduce Motion must stop the rig")
        require(scene.childNode(withName: "//sparks")?.children.isEmpty == true, "Reduce Motion must clear sparks")

        // Render at the actual companion sizes against real scene backgrounds.
        // Each state starts in a fresh scene so recovery and previous gestures cannot leak in.
        var comparisonCaptures = 0
        for side in [192.0, 128.0] {
            for (name, state, quota) in [("normal", SpiritState.idle, 1.0),
                                        ("tired", .idle, 0.05),
                                        ("depleted", .idle, 0.0),
                                        ("resting", .sleeping, 0.05)] {
                for background in ["light", "dark", "pattern"] {
                    let sample = SpiritScene(size: CGSize(width: side, height: side))
                    sample.provider = .codex
                    sample.isObserved = false
                    sample.tracksPointer = false
                    sample.remainingQuota = quota
                    sample.render(state: state, reduceMotion: false)
                    let backdrop = SKNode()
                    backdrop.name = "comparisonBackground"
                    backdrop.zPosition = -100
                    let base = SKSpriteNode(color: background == "dark"
                        ? NSColor(calibratedWhite: 0.08, alpha: 1)
                        : NSColor(calibratedWhite: 0.96, alpha: 1),
                        size: sample.size)
                    base.position = CGPoint(x: side / 2, y: side / 2)
                    backdrop.addChild(base)
                    if background == "pattern" {
                        let tileSide = 12.0
                        let palette: [NSColor] = [.systemBlue, .systemOrange, .systemGreen,
                                                 .systemPurple, .white, .darkGray]
                        for row in 0..<Int(ceil(side / tileSide)) {
                            for column in 0..<Int(ceil(side / tileSide)) {
                                let tile = SKSpriteNode(color: palette[(row * 3 + column) % palette.count],
                                    size: CGSize(width: tileSide, height: tileSide))
                                tile.position = CGPoint(x: Double(column) * tileSide + tileSide / 2,
                                                        y: Double(row) * tileSide + tileSide / 2)
                                backdrop.addChild(tile)
                            }
                        }
                    }
                    sample.addChild(backdrop)
                    view.frame = CGRect(x: 0, y: 0, width: side, height: side)
                    view.presentScene(sample)
                    view.isPaused = true
                    for frame in 0...300 { sample.update(Double(frame) / 60) }
                    require(sample.childNode(withName: "//body")?.alpha == 1,
                            "\(name) on \(background) must retain full body opacity")
                    require(sample.childNode(withName: "//eyes")?.yScale == 1,
                            "\(name) eyes must use dedicated expressions")
                    var questionMarkVisible = false
                    sample.enumerateChildNodes(withName: "//*") { node, _ in
                        if let label = node as? SKLabelNode, label.text == "?", !label.isHidden {
                            questionMarkVisible = true
                        }
                    }
                    require(!questionMarkVisible, "Unobserved \(name) must not show a question mark")
                    guard let texture = view.texture(from: sample,
                            crop: CGRect(x: 0, y: 0, width: side, height: side)),
                          let data = NSBitmapImageRep(cgImage: texture.cgImage())
                            .representation(using: .png, properties: [:])
                    else { fatalError("Actual-size \(name) snapshot failed") }
                    let path = output.appendingPathComponent("redesign-\(Int(side))-\(name)-\(background).png")
                    try data.write(to: path)
                    comparisonCaptures += 1
                    print("SNAPSHOT: \(path.path)")
                }
            }
        }
        for side in [128.0, 192.0] {
            let sample = SpiritScene(size: CGSize(width: side, height: side))
            sample.provider = .codex
            sample.tracksPointer = false
            sample.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1)
            sample.render(state: .working, reduceMotion: false)
            view.frame = CGRect(x: 0, y: 0, width: side, height: side)
            view.presentScene(sample)
            view.isPaused = true
            for frame in 0...39 { sample.update(Double(frame) / 60) }
            guard let texture = view.texture(from: sample, crop: view.bounds),
                  let data = NSBitmapImageRep(cgImage: texture.cgImage()).representation(using: .png, properties: [:])
            else { fatalError("Flying flame snapshot failed") }
            try data.write(to: output.appendingPathComponent("flying-flames-\(Int(side)).png"))
        }
        for side in [128.0, 192.0] {
            let sample = SpiritScene(size: CGSize(width: side, height: side))
            sample.provider = .codex
            sample.tracksPointer = false
            sample.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1)
            view.frame = CGRect(x: 0, y: 0, width: side, height: side)
            view.presentScene(sample)
            view.isPaused = true
            sample.beginPress()
            for frame in 0...180 {
                sample.update(Double(frame) / 60)
                if [90, 180].contains(frame) {
                    guard let texture = view.texture(from: sample, crop: view.bounds),
                          let data = NSBitmapImageRep(cgImage: texture.cgImage()).representation(using: .png, properties: [:])
                    else { fatalError("Power snapshot failed") }
                    try data.write(to: output.appendingPathComponent("power-\(Int(side))-\(frame).png"))
                }
            }
            require(sample.interactionCharge > 0.95, "Long hold must reach full charge")
            require((sample.childNode(withName: "//chargeAura")?.alpha ?? 0) > 0.2,
                    "Power must have a visible aura")
            sample.render(state: .idle, reduceMotion: true)
            sample.update(4)
            require(sample.childNode(withName: "//chargeAura")?.alpha == 0,
                    "Reduce Motion must suppress power aura")
        }
        let diverse = SpiritScene(size: CGSize(width: 192, height: 192))
        diverse.tracksPointer = false
        var seenFlames = Set<ObjectIdentifier>()
        var emittedFlames: [SKNode] = []
        var emitterBands = Set<Int>()
        for frame in 0..<1800 {
            diverse.update(Double(frame) / 60)
            for node in diverse.childNode(withName: "//sparks")!.children {
                if seenFlames.insert(ObjectIdentifier(node)).inserted {
                    emittedFlames.append(node) // Retain identities so deallocated sprite addresses cannot be reused.
                    emitterBands.insert(Int(node.position.y / 8))
                }
            }
        }
        require(emitterBands.count >= 4, "Embers must originate at feet, shoulders, temples and crown")
        require(comparisonCaptures == 24, "All 24 actual-size background comparisons must be written")
        // Measure the rendered flame itself, excluding breathing, blinking and particles.
        // A moving rig must not pass this test with an unchanged fire texture.
        let fire = SpiritScene(size: CGSize(width: 160, height: 160))
        fire.provider = .codex
        fire.tracksPointer = false
        view.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        view.presentScene(fire)
        view.isPaused = true
        let fireHead = fire.childNode(withName: "//head") as! SKSpriteNode
        let probe = SKSpriteNode(texture: fireHead.texture, size: CGSize(width: 336, height: 312))
        probe.shader = fireHead.shader
        func cells() -> [Int] {
            let bitmap = NSBitmapImageRep(cgImage: view.texture(from: probe)!.cgImage())
            return (0..<39).flatMap { row in
                (0..<42).map { column in
                    let color = bitmap.colorAt(x: (column * 2 + 1) * bitmap.pixelsWide / 84,
                                               y: (row * 2 + 1) * bitmap.pixelsHigh / 78)!
                    return color.alphaComponent < 0.5 ? 0
                        : 1 + Int(color.greenComponent * 255)
                }
            }
        }
        let gifURL = output.appendingPathComponent("fine-dot-flame-160.gif")
        let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, "com.compuserve.gif" as CFString, 30, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        var firstCells: [Int] = []
        var silhouetteChanges = 0
        var colorChanges = 0
        for frame in 0..<120 {
            fire.update(Double(frame) / 60)
            if frame.isMultiple(of: 4) {
                let next = cells()
                if firstCells.isEmpty { firstCells = next }
                silhouetteChanges = max(silhouetteChanges, zip(firstCells, next).filter { ($0 == 0) != ($1 == 0) }.count)
                colorChanges = max(colorChanges, zip(firstCells, next).filter { $0 > 0 && $1 > 0 && $0 != $1 }.count)
                let frameImage = view.texture(from: fire, crop: view.bounds)!.cgImage()
                CGImageDestinationAddImage(gif, frameImage, [kCGImagePropertyGIFDictionary:
                    [kCGImagePropertyGIFDelayTime: 4.0 / 60]] as CFDictionary)
            }
        }
        require(CGImageDestinationFinalize(gif), "Flame animation preview must be written")
        require(silhouetteChanges >= 25, "Idle fire must visibly reshape its outline on the fine grid")
        require(colorChanges >= 25, "Hot inner layers must flow independently of the rigid face")
        fire.render(state: .idle, reduceMotion: true)
        fire.update(2)
        let frozenCells = cells()
        for frame in 1...60 { fire.update(2 + Double(frame) / 60) }
        require(cells() == frozenCells, "Reduce Motion must freeze the rendered flame pixels")
        print("PASS: fine flame silhouette changes \(silhouetteChanges) cells; hot layers change \(colorChanges) cells; reduced motion freezes pixels")
        print("PASS: independent rig, hammer arc, idle recovery, reduced motion; snapshots: \(output.path)")
    }
}
