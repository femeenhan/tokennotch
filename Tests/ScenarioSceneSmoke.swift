import AppKit
import SpriteKit
import ImageIO
import SpiritCore

@main
@MainActor
struct ScenarioSceneSmoke {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func require(_ value: Bool, _ message: String) { precondition(value, message) }
        for side in [80.0, 128.0, 192.0] {
            for light in [false, true] {
                let view = SKView(frame: CGRect(x: 0, y: 0, width: side, height: side))
                for scenario in ["gaze", "petting", "drag", "work", "completion", "ember", "attention-error", "rest"] {
                    if CommandLine.arguments.count > 2 && !CommandLine.arguments.dropFirst(2).contains(scenario) { continue }
                    let scene = SpiritScene(size: view.frame.size)
                    scene.tracksPointer = false
                    scene.automaticallyPlaysHammerTricks = false
                    scene.backgroundColor = NSColor(calibratedWhite: light ? 0.94 : 0.10, alpha: 1)
                    view.presentScene(scene)
                    view.isPaused = true
                    scene.update(0)
                    require(scene.assetLoaded, "Production assets must load")
                    let hammer = scene.childNode(withName: "//hammer")!
                    let stage = scene.childNode(withName: "stage")!
                    let body = scene.childNode(withName: "//body")!
                    let prop = scene.childNode(withName: "//workSurface")!
                    let ember = scene.childNode(withName: "//storyEmber")!
                    require(hammer.parent === stage, "Rigid tool must not inherit body squash")
                    require(ember.parent === stage, "Story ember must move independently from the hand")
                    if scenario == "work" { scene.render(state: .working, reduceMotion: false) }
                    if scenario == "completion" { scene.render(state: .completed, reduceMotion: false) }
                    if scenario == "ember" { require(scene.playEmberPlay(), "Ember episode must start") }
                    if scenario == "attention-error" { scene.render(state: .attention, reduceMotion: false) }
                    if scenario == "rest" { scene.render(state: .sleeping, reduceMotion: false) }
                    if scenario == "drag" { scene.setDragging(true) }
                    let name = "\(scenario)-\(Int(side))-\(light ? "light" : "dark")"
                    let gif = CGImageDestinationCreateWithURL(output.appendingPathComponent(name + ".gif") as CFURL,
                        "com.compuserve.gif" as CFString, 80, nil)!
                    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                    var sawProp = false
                    var sawEmber = false
                    var expressions = Set<String>()
                    for frame in 1...300 {
                        if scenario == "gaze" { scene.setPointer(x: frame < 100 ? 32 : nil, y: frame < 100 ? 40 : nil) }
                        if scenario == "petting" { scene.setPointer(x: frame < 100 ? sin(Double(frame) / 10) * 10 : nil,
                            y: frame < 100 ? 44 : nil, velocityX: frame < 100 ? 45 : 0) }
                        if scenario == "drag" {
                            if frame < 40 { scene.setDragVelocity(x: 180, y: 70) }
                            if frame == 100 { scene.setDragging(false) }
                            let x = hammer.convert(CGPoint(x: 1, y: 0), to: stage)
                            let y = hammer.convert(CGPoint(x: 0, y: 1), to: stage)
                            let origin = hammer.convert(.zero, to: stage)
                            require(abs(hypot(x.x-origin.x, x.y-origin.y)-hypot(y.x-origin.x, y.y-origin.y)) < 0.0001,
                                    "Hammer axes must retain equal scale during drag")
                        }
                        if scenario == "attention-error" && frame == 150 { scene.render(state: .error, reduceMotion: false) }
                        if scenario == "rest" && frame == 240 { scene.render(state: .idle, reduceMotion: false); scene.setPointer(x: 30, y: 40) }
                        scene.update(Double(frame) / 60)
                        expressions.insert(String(describing: scene.displayedExpression))
                        sawProp = sawProp || prop.alpha > 0.9
                        sawEmber = sawEmber || ember.alpha > 0.9
                        if frame.isMultiple(of: 4) {
                            let image = view.texture(from: scene, crop: view.bounds)!.cgImage()
                            CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 15]] as CFDictionary)
                            if [28, 60, 68, 100, 132, 180, 240, 300].contains(frame) {
                                try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                                    .write(to: output.appendingPathComponent("\(name)-\(frame).png"))
                            }
                        }
                    }
                    require(CGImageDestinationFinalize(gif), "GIF export must succeed")
                    if scenario == "work" { require(sawProp && expressions.contains("focused"), "Work needs target and focus") }
                    if scenario == "ember" { require(sawEmber && ember.alpha == 0 && expressions.contains("proud"), "Ember must appear, be caught, and leave") }
                    if scenario == "attention-error" { require(expressions.contains("requesting") && expressions.contains("worried"), "Attention and error must differ") }
                    if scenario == "rest" { require(expressions.contains("yawning") && expressions.contains("sleeping") && body.yScale > 0.95, "Rest must yawn, sleep, and wake") }
                    scene.cancelInteractions()
                    scene.render(state: .error, reduceMotion: true)
                    scene.update(6)
                    let fixed = (body.position, body.xScale, body.yScale)
                    scene.update(6.1)
                    require(scene.displayedExpression == .worried && ember.alpha == 0,
                            "Reduced motion retains meaning without story effects")
                    require(body.position == fixed.0 && body.xScale == fixed.1 && body.yScale == fixed.2, "Reduced body stays still")
                }
            }
        }
        let selected = CommandLine.arguments.count > 2 ? CommandLine.arguments.dropFirst(2).joined(separator: ", ") : "all eight scenarios"
        print("PASS: \(selected) at 80/128/192pt on light/dark, rigid hammer, props, expressions and reduced motion. \(output.path)")
    }
}
