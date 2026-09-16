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
        view.isPaused = true
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        func require(_ condition: Bool, _ message: String) {
            if !condition { fatalError(message) }
        }
        require(scene.assetLoaded, "Rig atlas failed to load")
        let hammer = scene.childNode(withName: "//hammer")
        let head = scene.childNode(withName: "//head")
        let eyes = scene.childNode(withName: "//eyes")
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
        scene.render(state: .working, reduceMotion: true)
        time += 1.0 / 60; scene.update(time)
        let still = hammer!.zRotation
        for _ in 0..<120 { time += 1.0 / 60; scene.update(time) }
        require(hammer!.zRotation == still, "Reduce Motion must stop the rig")
        require(scene.childNode(withName: "//sparks")?.children.isEmpty == true, "Reduce Motion must clear sparks")
        print("PASS: independent rig, hammer arc, idle recovery, reduced motion; snapshots: \(output.path)")
    }
}
