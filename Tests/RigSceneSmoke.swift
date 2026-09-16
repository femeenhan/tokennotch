import AppKit
import SpriteKit
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
        var time = 0.0
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for frame in 0...100 {
            time = Double(frame) / 60
            scene.update(time)
            require(body.alpha == 1, "Working spirit body must remain fully opaque")
            angles.append(hammer!.zRotation)
            sawSparks = sawSparks || !(scene.childNode(withName: "//sparks")?.children.isEmpty ?? true)
            if [0, 24, 35, 39, 60, 90].contains(frame) {
                guard let texture = view.texture(from: scene, crop: view.bounds),
                      let data = NSBitmapImageRep(cgImage: texture.cgImage()).representation(using: .png, properties: [:])
                else { fatalError("Frame \(frame) could not be captured") }
                try data.write(to: output.appendingPathComponent("forge-\(frame).png"))
                captured += 1
            }
        }
        require(captured == 6, "All six rendered snapshots must be written")
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
        require(comparisonCaptures == 24, "All 24 actual-size background comparisons must be written")
        print("PASS: independent rig, hammer arc, idle recovery, reduced motion; snapshots: \(output.path)")
    }
}
