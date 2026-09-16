import AppKit
import SpriteKit
import SpiritCore

/// Cutout rig on a 64pt stage; each part has its own pivot and motion.
@MainActor
final class SpiritScene: SKScene {
    private let stage = SKNode()
    private let body = SKNode()
    private let head = SKSpriteNode()
    private let eyes = SKNode()
    private let hammer = SKNode()
    private let freeArm = SKNode()
    private let sparks = SKNode()
    private let statusBackground = SKShapeNode()
    private let statusLabel = SKLabelNode(fontNamed: "AppleSDGothicNeo-SemiBold")
    private var motion = SpiritRigMotion()
    private var previousTime: TimeInterval?
    private var reducedMotion = false
    private var particles: [(node: SKSpriteNode, age: Double, vx: Double, vy: Double)] = []
    private(set) var spiritState: SpiritState = .idle
    private(set) var assetLoaded = false
    var playbackRate: Double = 1

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        addChild(stage)
        stage.addChild(body)
        stage.addChild(sparks)
        body.name = "body"
        head.name = "head"
        eyes.name = "eyes"
        hammer.name = "hammer"
        freeArm.name = "freeArm"
        sparks.name = "sparks"
        buildRig()
        statusBackground.fillColor = NSColor.black.withAlphaComponent(0.72)
        statusBackground.strokeColor = .clear
        statusBackground.zPosition = 20
        addChild(statusBackground)
        statusLabel.fontColor = .white
        statusLabel.verticalAlignmentMode = .center
        statusLabel.horizontalAlignmentMode = .center
        statusLabel.zPosition = 21
        addChild(statusLabel)
        layoutSpirit()
        render(state: .idle, reduceMotion: false)
    }

    required init?(coder: NSCoder) { nil }

    private func buildRig() {
        guard let url = Bundle.main.url(forResource: "smith-rig-atlas", withExtension: "png", subdirectory: "Spirit"),
              let image = NSImage(contentsOf: url) else { return }
        let atlas = SKTexture(image: image)
        atlas.filteringMode = .nearest
        // Measured pixel rectangles on the 1254px atlas, with a top-left origin.
        // Preserve the generated alpha; never erase white from the cream highlights.
        func part(_ rect: CGRect, scale: CGFloat) -> SKSpriteNode {
            let texture = SKTexture(rect: CGRect(x: rect.minX / 1254, y: 1 - rect.maxY / 1254,
                                                width: rect.width / 1254, height: rect.height / 1254), in: atlas)
            texture.filteringMode = .nearest
            return SKSpriteNode(texture: texture, size: CGSize(width: rect.width * scale, height: rect.height * scale))
        }
        let unit: CGFloat = 48 / 672
        let torso = part(CGRect(x: 170, y: 500, width: 368, height: 230), scale: unit)
        torso.anchorPoint = CGPoint(x: 0.5, y: 0)
        torso.zPosition = 1
        body.addChild(torso)
        let headPart = part(CGRect(x: 104, y: 53, width: 495, height: 480), scale: unit)
        head.texture = headPart.texture
        head.size = headPart.size
        head.anchorPoint = CGPoint(x: 0.5, y: 0)
        head.position = CGPoint(x: 0, y: 197 * unit)
        head.zPosition = 2
        head.subdivisionLevels = 3
        body.addChild(head)
        eyes.position = CGPoint(x: 0, y: 9.1)
        eyes.zPosition = 2
        head.addChild(eyes)
        for (rect, x) in [(CGRect(x: 756, y: 927, width: 94, height: 127), -6.8),
                          (CGRect(x: 1026, y: 927, width: 95, height: 127), 6.8)] {
            let eye = part(rect, scale: 0.044)
            eye.position.x = x
            eyes.addChild(eye)
        }
        let mouth = part(CGRect(x: 886, y: 1035, width: 108, height: 42), scale: 0.044)
        mouth.position = CGPoint(x: 0, y: 5.1)
        mouth.zPosition = 2
        head.addChild(mouth)
        // Shoulder pivot at the right end, not the centre of the hammer image.
        let tool = part(CGRect(x: 807, y: 255, width: 312, height: 396), scale: 0.047)
        tool.anchorPoint = CGPoint(x: 0.90, y: 0.25)
        hammer.addChild(tool)
        hammer.position = CGPoint(x: -9, y: 11.5)
        hammer.zPosition = 4
        body.addChild(hammer)
        let arm = part(CGRect(x: 245, y: 892, width: 213, height: 233), scale: 0.039)
        arm.anchorPoint = CGPoint(x: 0.16, y: 0.89)
        freeArm.addChild(arm)
        freeArm.position = CGPoint(x: 9.4, y: 12.2)
        freeArm.zPosition = 3
        body.addChild(freeArm)
        sparks.zPosition = 8
        assetLoaded = true
    }

    override func didChangeSize(_ oldSize: CGSize) { layoutSpirit() }

    private func layoutSpirit() {
        let side = min(size.width, size.height)
        stage.setScale(side / 64)
        stage.position = CGPoint(x: size.width / 2 + side * 0.04, y: side * 0.13)
        statusLabel.fontSize = max(9, side * 0.064)
        statusLabel.position = CGPoint(x: size.width / 2, y: side * 0.055)
        statusBackground.position = statusLabel.position
        updateStatusBackground()
    }

    private func updateStatusBackground() {
        let labelSize = statusLabel.frame.size
        statusBackground.path = CGPath(roundedRect: CGRect(
            x: -(labelSize.width + 16) / 2, y: -(labelSize.height + 7) / 2,
            width: labelSize.width + 16, height: labelSize.height + 7
        ), cornerWidth: 5, cornerHeight: 5, transform: nil)
    }

    func render(state: SpiritState, reduceMotion: Bool) {
        spiritState = state
        statusLabel.text = SpiritPresentation(state: state).label
        updateStatusBackground()
        motion.setState(state)
        reducedMotion = reduceMotion
        if reduceMotion {
            particles.removeAll()
            sparks.removeAllChildren()
            apply(motion.advance(by: 0, reduceMotion: true))
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let delta = previousTime.map { min(max(currentTime - $0, 0), 1.0 / 15) } ?? 0
        previousTime = currentTime
        // Match the motion engine's resume clamp so particles never run ahead of the rig.
        let elapsed = min(delta * min(max(playbackRate, 0.25), 1.5), 1.0 / 20)
        let pose = motion.advance(by: elapsed, reduceMotion: reducedMotion)
        apply(pose)
        if pose.didStrike && !reducedMotion { emitSparks() }
        updateSparks(by: elapsed)
    }

    private func apply(_ pose: SpiritRigPose) {
        body.position.y = pose.bodyOffsetY
        body.yScale = pose.bodyScaleY
        head.zRotation = pose.headAngle
        hammer.zRotation = pose.hammerAngle
        freeArm.zRotation = pose.freeArmAngle
        eyes.yScale = pose.eyeOpen
        eyes.position.x = pose.gazeX
        // Keep the lower face rigid. Only the upper flame flows through this mesh.
        let count = 6
        var source: [SIMD2<Float>] = []
        var destination: [SIMD2<Float>] = []
        for row in 0...count {
            for column in 0...count {
                let x = Float(column) / Float(count)
                let y = Float(row) / Float(count)
                let weight = max(0, (y - 0.43) / 0.57)
                source.append(SIMD2(x, y))
                destination.append(SIMD2(x + Float(pose.flameSway) * weight * weight,
                                         y + Float(pose.flameStretch - 1) * weight * 0.65))
            }
        }
        head.warpGeometry = SKWarpGeometryGrid(columns: count, rows: count,
                                              sourcePositions: source, destinationPositions: destination)
    }

    private func emitSparks() {
        let contact = hammer.convert(CGPoint(x: -8, y: 12), to: stage)
        for index in 0..<7 {
            let pixel = SKSpriteNode(color: index.isMultiple(of: 2)
                ? NSColor(red: 1, green: 0.84, blue: 0.25, alpha: 1)
                : NSColor(red: 1, green: 0.39, blue: 0.10, alpha: 1),
                size: CGSize(width: 0.7, height: 0.7))
            pixel.position = contact
            sparks.addChild(pixel)
            particles.append((pixel, 0, Double(index - 3) * 5, 10 + Double(index % 3) * 5))
        }
    }

    private func updateSparks(by delta: Double) {
        for index in particles.indices {
            particles[index].age += delta
            let p = particles[index]
            p.node.position.x += p.vx * delta
            p.node.position.y += (p.vy - 55 * p.age) * delta
            p.node.alpha = max(0, 1 - p.age / 0.42)
        }
        particles.removeAll { particle in
            if particle.age >= 0.42 { particle.node.removeFromParent(); return true }
            return false
        }
    }
}
