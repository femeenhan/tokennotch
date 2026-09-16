import AppKit
import SpriteKit
import CoreText
import SpiritCore

/// Cutout rig on a 64pt stage; each part has its own pivot and motion.
@MainActor
final class SpiritScene: SKScene {
    private let stage = SKNode()
    private let body = SKNode()
    private let head = SKSpriteNode()
    private let aura = SKSpriteNode()
    private let mouth = SKSpriteNode()
    private let eyes = SKNode()
    private let openEyes = SKNode()
    private let tiredEyes = SKNode()
    private let closedEyes = SKNode()
    private var flameParts: [SKSpriteNode] = []
    private let coreGlow = SKSpriteNode(color: .yellow, size: CGSize(width: 7, height: 9))
    private let heldEmber = SKSpriteNode(color: .yellow, size: CGSize(width: 1.4, height: 1.4))
    private var previousPointer: CGPoint?
    var remainingQuota: Double? { didSet { motion.setRemainingQuota(remainingQuota) } }
    private let hammer = SKNode()
    private let freeArm = SKNode()
    private let sparks = SKNode()
    private let statusBackground = SKShapeNode()
    private let statusLabel = SKSpriteNode()
    private var identityText = ""
    var provider: SpiritProvider? { didSet { updateIdentity() } }
    var isObserved = true { didSet { updateIdentity() } }
    var displayedLabel: String { identityText }
    private let stateBadge = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    private var motion = SpiritRigMotion()
    private var flameTime = 0.0
    private var chargeEmissionTime = 0.0
    private var emitterIndex = 0
    private var baseStageScale: CGFloat = 1
    var onTransform: (() -> Void)?
    var effectTexture: SKTexture { flyingFlameTexture }
    var effectShader: SKShader? { motion.pose.charge > 0.08 ? chargeShader : nil }
    var interactionCharge: Double { motion.pose.charge }

    func beginPress() { motion.beginPress() }
    @discardableResult
    func endPress(registerTap: Bool) -> Bool { motion.endPress(registerTap: registerTap) }
    func setDragVelocity(x: Double, y: Double) {
        let scale = max(stage.xScale, 0.5)
        motion.setDragVelocity(x: x / scale, y: y / scale)
    }
    private var previousTime: TimeInterval?
    private var reducedMotion = false
    private let chargeUniform = SKUniform(name: "u_charge", float: 0)
    private lazy var chargeShader = SKShader(source: """
        void main() {
            vec4 source = SKDefaultShading();
            vec3 rgb = source.rgb / max(source.a, 0.001);
            vec3 gold;
            vec3 blue;
            if (rgb.g < 0.32) {
                gold = vec3(0.96, 0.45, 0.03);
                blue = vec3(0.12, 0.38, 0.83);
            } else if (rgb.g < 0.65) {
                gold = vec3(1.0, 0.72, 0.05);
                blue = vec3(0.17, 0.67, 0.95);
            } else if (rgb.b < 0.60) {
                gold = vec3(1.0, 0.90, 0.45);
                blue = vec3(0.54, 0.90, 1.0);
            } else {
                gold = vec3(1.0, 0.98, 0.85);
                blue = vec3(0.92, 1.0, 1.0);
            }
            vec3 palette = mix(gold, blue, smoothstep(0.72, 0.95, u_charge));
            gl_FragColor = vec4(mix(rgb, palette, min(1.0, u_charge * 2.0)) * source.a, source.a);
        }
        """, uniforms: [chargeUniform])
    private lazy var flyingFlameTexture = makeFlyingFlameTexture()
    private var particles: [(node: SKSpriteNode, age: Double, vx: Double, vy: Double, life: Double, gravity: Double)] = []
    private(set) var spiritState: SpiritState = .idle
    private(set) var assetLoaded = false
    var playbackRate: Double = 1
    var tracksPointer = true

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
        openEyes.name = "openEyes"
        tiredEyes.name = "tiredEyes"
        closedEyes.name = "closedEyes"
        stateBadge.name = "stateBadge"
        hammer.name = "hammer"
        freeArm.name = "freeArm"
        sparks.name = "sparks"
        buildRig()
        statusBackground.fillColor = NSColor.black.withAlphaComponent(0.72)
        statusBackground.strokeColor = .clear
        statusBackground.zPosition = 20
        addChild(statusBackground)
        statusLabel.name = "providerLabel"
        stage.name = "stage"
        if let url = Bundle.main.url(forResource: "neodgm", withExtension: "ttf", subdirectory: "Spirit/Fonts") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        statusLabel.zPosition = 21
        addChild(statusLabel)
        stateBadge.fontSize = 11
        stateBadge.fontColor = .white
        stateBadge.zPosition = 22
        addChild(stateBadge)
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
        flameParts.append(torso)
        let headPart = part(CGRect(x: 104, y: 53, width: 495, height: 480), scale: unit)
        head.texture = headPart.texture
        head.size = headPart.size
        head.anchorPoint = CGPoint(x: 0.5, y: 0)
        head.position = CGPoint(x: 0, y: 197 * unit)
        head.zPosition = 2
        head.subdivisionLevels = 3
        body.addChild(head)
        flameParts.append(head)
        aura.name = "chargeAura"
        aura.texture = head.texture
        aura.size = head.size
        aura.anchorPoint = head.anchorPoint
        aura.position = head.position
        aura.zPosition = 1.5
        aura.colorBlendFactor = 1
        aura.alpha = 0
        body.addChild(aura)
        eyes.position = CGPoint(x: 0, y: 9.1)
        eyes.zPosition = 2
        head.addChild(eyes)
        eyes.addChild(openEyes)
        eyes.addChild(tiredEyes)
        eyes.addChild(closedEyes)
        for (rect, x) in [(CGRect(x: 756, y: 927, width: 94, height: 127), -6.8),
                          (CGRect(x: 1026, y: 927, width: 95, height: 127), 6.8)] {
            let eye = part(rect, scale: 0.044)
            eye.position.x = x
            openEyes.addChild(eye)
        }
        // Pixel eyelids have their own geometry: no squashed pupils or highlights.
        let ink = NSColor(red: 0.29, green: 0.16, blue: 0.08, alpha: 1)
        func pixel(_ parent: SKNode, x: Double, y: Double, width: Double, height: Double,
                   color: NSColor = NSColor(red: 0.29, green: 0.16, blue: 0.08, alpha: 1)) {
            let node = SKSpriteNode(color: color, size: CGSize(width: width, height: height))
            node.position = CGPoint(x: x, y: y)
            parent.addChild(node)
        }
        for x in [-6.8, 6.8] {
            // Half-lidded eyes retain a full-size small pupil and a single glint.
            pixel(tiredEyes, x: x, y: -0.6, width: 3.6, height: 2.8)
            pixel(tiredEyes, x: x, y: 0.9, width: 4.6, height: 0.9)
            pixel(tiredEyes, x: x + 0.5, y: -0.2, width: 0.9, height: 1.2,
                  color: NSColor(red: 1, green: 0.89, blue: 0.60, alpha: 1))
            // Closed eyes form a calm, stepped curve, readable at 128pt.
            pixel(closedEyes, x: x, y: -0.6, width: 3.3, height: 0.95, color: ink)
            pixel(closedEyes, x: x - 2, y: 0.05, width: 0.95, height: 0.95, color: ink)
            pixel(closedEyes, x: x + 2, y: 0.05, width: 0.95, height: 0.95, color: ink)
        }
        let mouthPart = part(CGRect(x: 886, y: 1035, width: 108, height: 42), scale: 0.044)
        mouth.texture = mouthPart.texture
        mouth.size = mouthPart.size
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
        flameParts.append(arm)
        freeArm.position = CGPoint(x: 9.4, y: 12.2)
        freeArm.zPosition = 3
        body.addChild(freeArm)
        // A stepped, fading pixel ember avoids a rectangular highlight on the face.
        let glowImage = NSImage(size: CGSize(width: 9, height: 11))
        glowImage.lockFocus()
        NSGraphicsContext.current?.shouldAntialias = false
        for y in 0..<11 {
            for x in 0..<9 {
                let distance = abs(Double(x - 4)) / 5 + abs(Double(y - 5)) / 6
                NSColor.white.withAlphaComponent(max(0, 1 - distance) * 0.65).setFill()
                NSRect(x: x, y: y, width: 1, height: 1).fill()
            }
        }
        glowImage.unlockFocus()
        coreGlow.texture = SKTexture(image: glowImage)
        coreGlow.texture?.filteringMode = .nearest
        coreGlow.colorBlendFactor = 1
        coreGlow.name = "coreGlow"
        coreGlow.position = CGPoint(x: 0, y: 20)
        coreGlow.zPosition = 2.1
        coreGlow.blendMode = .add
        coreGlow.alpha = 0
        body.addChild(coreGlow)
        heldEmber.name = "heldEmber"
        heldEmber.position = CGPoint(x: 4, y: 1)
        freeArm.addChild(heldEmber)
        heldEmber.alpha = 0
        sparks.zPosition = 8
        assetLoaded = true
    }

    override func didChangeSize(_ oldSize: CGSize) { layoutSpirit() }

    private func layoutSpirit() {
        let side = min(size.width, size.height)
        stage.setScale(side / 64)
        stage.position = CGPoint(x: size.width / 2 + side * 0.04, y: side * 0.13)
        statusLabel.position = CGPoint(x: stage.position.x, y: side * 0.055)
        statusBackground.position = statusLabel.position
        stateBadge.position = CGPoint(x: stage.position.x, y: side * 0.17)
        updateStatusTexture()
    }

    private func updateStatusTexture() {
        // Rasterize at the font’s native pixel grid; CoreText reports a zero global
        // bounding box for this font, so SKLabelNode cannot lay it out reliably.
        let fontSize = max(16, (min(size.width, size.height) * 0.10 / 8).rounded() * 8)
        let font = NSFont(name: "NeoDunggeunmo-Regular", size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let text = NSAttributedString(string: identityText, attributes: [.font: font, .foregroundColor: NSColor.white])
        let extent = text.size()
        let image = NSImage(size: CGSize(width: max(1, ceil(extent.width) + 2), height: max(1, ceil(extent.height) + 4)))
        image.lockFocus()
        NSGraphicsContext.current?.shouldAntialias = false
        text.draw(at: CGPoint(x: 1, y: 2))
        image.unlockFocus()
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        statusLabel.texture = texture
        statusLabel.size = image.size
        let side = min(size.width, size.height)
        let nameplateHeight = image.size.height + 7
        statusLabel.position.y = max(side * 0.055, nameplateHeight / 2 + 2)
        statusBackground.position = statusLabel.position
        // Reserve room for the larger nameplate without covering the feet.
        stage.position.y = max(side * 0.13, statusLabel.position.y + nameplateHeight / 2 + 4)
        baseStageScale = min(side / 64, (side - stage.position.y) / 50)
        stage.setScale(baseStageScale)
        stateBadge.position = CGPoint(x: statusLabel.position.x + image.size.width / 2 + 9,
                                      y: statusLabel.position.y - 4)
        updateStatusBackground()
    }

    private func updateStatusBackground() {
        let labelSize = statusLabel.frame.size
        let badgeWidth: CGFloat = stateBadge.isHidden ? 0 : 17
        statusBackground.path = CGPath(roundedRect: CGRect(
            x: -(labelSize.width + 16) / 2, y: -(labelSize.height + 7) / 2,
            width: labelSize.width + 16 + badgeWidth, height: labelSize.height + 7
        ), cornerWidth: 0, cornerHeight: 0, transform: nil)
    }

    func render(state: SpiritState, reduceMotion: Bool) {
        spiritState = state
        updateIdentity()
        motion.setState(state)
        reducedMotion = reduceMotion
        if reduceMotion {
            particles.removeAll()
            sparks.removeAllChildren()
            apply(motion.advance(by: 0, reduceMotion: true))
        }
    }

    private func updateIdentity() {
        identityText = provider?.displayName ?? SpiritPresentation(state: spiritState).label
        switch spiritState {
        case .attention: stateBadge.text = "!"
        case .error: stateBadge.text = "×"
        case .working: stateBadge.text = "▶"
        case .completed: stateBadge.text = "✓"
        default: stateBadge.text = ""
        }
        stateBadge.isHidden = provider == nil || stateBadge.text?.isEmpty != false
        updateStatusTexture()
    }

    override func update(_ currentTime: TimeInterval) {
        let delta = previousTime.map { min(max(currentTime - $0, 0), 1.0 / 15) } ?? 0
        previousTime = currentTime
        // Match the motion engine's resume clamp so particles never run ahead of the rig.
        let elapsed = min(delta * min(max(playbackRate, 0.25), 1.5), 1.0 / 20)
        if tracksPointer && !reducedMotion, let view, let window = view.window {
            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let scenePoint = convertPoint(fromView: view.convert(windowPoint, from: nil))
            let point = stage.convert(scenePoint, from: self)
            let velocity = previousPointer.map { CGPoint(x: (point.x - $0.x) / max(delta, 0.001),
                                                        y: (point.y - $0.y) / max(delta, 0.001)) } ?? .zero
            motion.setPointer(x: point.x, y: point.y, velocityX: velocity.x, velocityY: velocity.y)
            previousPointer = point
        }
        if !reducedMotion { flameTime += elapsed }
        let pose = motion.advance(by: elapsed, reduceMotion: reducedMotion)
        apply(pose)
        if !reducedMotion {
            if pose.didTransform { onTransform?(); emitEmbers(count: 14, celebration: true, heat: 1) }
            chargeEmissionTime += elapsed
            if pose.charge > 0.1 && chargeEmissionTime > 0.15 {
                emitEmbers(count: 3, celebration: false, heat: 1)
                chargeEmissionTime = 0
            }
            if pose.didStrike { emitSparks() }
            if pose.didCelebrate { emitEmbers(count: 16, celebration: true, heat: pose.heat) }
            if pose.didEmitEmber { emitEmbers(count: spiritState == .working ? 2 : 1, celebration: false, heat: pose.heat) }
        }
        updateSparks(by: elapsed)
    }

    private func apply(_ pose: SpiritRigPose) {
        stage.setScale(baseStageScale * (1 - pose.charge * 0.10))
        body.position.y = pose.bodyOffsetY
        body.yScale = pose.bodyScaleY
        head.zRotation = pose.headAngle
        head.position.y = 197 * (48.0 / 672) - pose.restAmount * 0.45
        hammer.position.y = 11.5 - pose.restAmount * 1.2
        freeArm.position.y = 12.2 - pose.restAmount * 0.7
        hammer.zRotation = pose.hammerAngle
        freeArm.zRotation = pose.freeArmAngle
        eyes.yScale = 1
        let closed = pose.eyeOpen < 0.25 || pose.restAmount > 0.65
        let tired = !closed && (pose.vitality < 0.6 || pose.eyeOpen < 0.7)
        openEyes.isHidden = closed || tired
        tiredEyes.isHidden = !tired
        closedEyes.isHidden = !closed
        mouth.yScale = pose.mouthOpen
        eyes.position.x = pose.gazeX
        eyes.position.y = 9.1 + pose.gazeY
        chargeUniform.floatValue = Float(pose.charge)
        let powerColor = pose.charge > 0.82
            ? NSColor(red: 0.35, green: 0.84, blue: 1, alpha: 1)
            : NSColor(red: 1, green: 0.84, blue: 0.20, alpha: 1)
        aura.color = powerColor
        aura.position = head.position
        aura.zRotation = head.zRotation
        aura.setScale(1 + pose.charge * 0.13)
        aura.alpha = pose.charge * (0.25 + 0.025 * sin(flameTime * 5))
        let cooling = min(1, (1 - pose.vitality) * 0.8 + pose.restAmount * 0.2)
        for part in flameParts {
            part.color = NSColor(red: 0.78, green: 0.35, blue: 0.12, alpha: 1)
            part.colorBlendFactor = cooling * 0.24
            part.shader = pose.charge > 0.08 ? chargeShader : nil
            if pose.charge > 0.08 { part.colorBlendFactor = 0 }
        }
        coreGlow.color = NSColor(red: 1 - pose.heat * 0.55, green: 0.85 + pose.heat * 0.15, blue: 0.3 + pose.heat * 0.7, alpha: 1)
        coreGlow.alpha = min(0.8, (0.10 + 0.25 * pose.heat + 0.3 * pose.impact) * pose.emberGlow + pose.charge * 0.25)
        coreGlow.yScale = 0.4 + 0.6 * pose.vitality
        body.alpha = 1
        heldEmber.alpha = pose.heldEmber
        heldEmber.setScale(0.6 + pose.heldEmber * 0.4)
        // Keep the lower face rigid. Only the upper flame flows through this mesh.
        let count = 6
        var source: [SIMD2<Float>] = []
        var destination: [SIMD2<Float>] = []
        for row in 0...count {
            for column in 0...count {
                let x = Float(column) / Float(count)
                let y = Float(row) / Float(count)
                let weight = max(0, (y - 0.68) / 0.32)
                source.append(SIMD2(x, y))
                let ripple = reducedMotion ? Float(0) : 0.012 * sin(Float(flameTime) * 5 + x * 13) * weight * weight
                destination.append(SIMD2(x + Float(pose.flameSway) * weight * weight + ripple,
                                         y + Float(pose.flameStretch - 1) * weight * 0.65))
            }
        }
        head.warpGeometry = SKWarpGeometryGrid(columns: count, rows: count,
                                              sourcePositions: source, destinationPositions: destination)
        aura.warpGeometry = head.warpGeometry
    }

    /// A tiny cutout flame with an orange silhouette, golden core and cream tip.
    /// Nearest filtering keeps the layered shape readable at desktop sizes.
    private func makeFlyingFlameTexture() -> SKTexture {
        let rows = ["0001000", "0011000", "0012100", "0122100", "0123210",
                    "1123210", "1233221", "1233321", "1233321", "0122210", "0011100"]
        let colors: [NSColor] = [.clear,
            NSColor(red: 0.96, green: 0.29, blue: 0.06, alpha: 1),
            NSColor(red: 1, green: 0.70, blue: 0.12, alpha: 1),
            NSColor(red: 1, green: 0.96, blue: 0.70, alpha: 1)]
        let image = NSImage(size: CGSize(width: 7, height: 11))
        image.lockFocus()
        NSGraphicsContext.current?.shouldAntialias = false
        for (row, pixels) in rows.enumerated() {
            for (column, digit) in pixels.enumerated() {
                guard let index = digit.wholeNumberValue, index > 0 else { continue }
                colors[index].setFill()
                NSRect(x: column, y: 10 - row, width: 1, height: 1).fill()
            }
        }
        image.unlockFocus()
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }

    private func flyingFlame(size: Double, heat: Double = 0) -> SKSpriteNode {
        let flame = SKSpriteNode(texture: flyingFlameTexture,
                                 size: CGSize(width: size, height: size * 11 / 7))
        flame.name = "flyingFlame"
        if motion.pose.charge > 0.08 {
            flame.shader = chargeShader
        } else if heat > 0.7 {
            flame.color = NSColor(red: 1, green: 0.9, blue: 0.6, alpha: 1)
            flame.colorBlendFactor = 0.15
        }
        let tail = SKSpriteNode(color: NSColor(red: 1, green: 0.48, blue: 0.08, alpha: 0.5),
                               size: CGSize(width: size * 0.30, height: size * 1.5))
        tail.name = "flameTail"
        tail.anchorPoint = CGPoint(x: 0.5, y: 1)
        tail.position.y = -size * 0.25
        tail.zPosition = -1
        flame.addChild(tail)
        return flame
    }

    private func emitSparks() {
        let contact = hammer.convert(CGPoint(x: -8, y: 12), to: stage)
        for index in 0..<7 {
            let pixel = flyingFlame(size: index.isMultiple(of: 2) ? 1.5 : 1.1)
            pixel.position = contact
            sparks.addChild(pixel)
            particles.append((pixel, 0, Double(index - 3) * 6, 14 + Double(index % 3) * 5, 0.65, 48))
        }
    }

    private func emitEmbers(count: Int, celebration: Bool, heat: Double) {
        guard particles.count < 80 else { return }
        for index in 0..<count {
            let pixel = flyingFlame(size: celebration ? Double.random(in: 1.8...2.5) : Double.random(in: 1.8...2.3), heat: heat)
            // Crown, temples, shoulders and feet all contribute a distinct little jet.
            let emitters: [(Double, Double, Double, Double)] = [
                (-15, 32, -8, 9), (7, 43, 3, 9), (12, 13, 7, 8),
                (-7, 3, -4, 10), (-7, 44, -3, 9), (16, 23, 8, 8),
                (0, 46, 0, 9), (-12, 13, -7, 8), (7, 3, 4, 10),
                (15, 32, 8, 9), (-16, 23, -8, 8)]
            let emitter = emitters[emitterIndex % emitters.count]
            emitterIndex += 1
            pixel.position = CGPoint(x: celebration ? 0 : emitter.0 + Double.random(in: -1...1),
                                     y: celebration ? 28 : emitter.1 + Double.random(in: -1...1))
            sparks.addChild(pixel)
            let angle = Double(index) / Double(max(count, 1)) * .pi * 2
            particles.append((pixel, 0, celebration ? cos(angle) * 22 : emitter.2 + Double.random(in: -2...2),
                              celebration ? sin(angle) * 18 + 8 : emitter.3, 1.5, celebration ? 8 : -0.5))
        }
    }

    private func updateSparks(by delta: Double) {
        for index in particles.indices {
            particles[index].age += delta
            let p = particles[index]
            p.node.position.x += p.vx * delta
            p.node.position.y += (p.vy - p.gravity * p.age) * delta
            let progress = p.age / p.life
            // Hold a bright, readable core, then shrink into an ember as it fades.
            p.node.alpha = max(0, min(1, (1 - progress) / 0.45))
            p.node.xScale = 1 - 0.35 * progress
            p.node.yScale = (1 - 0.25 * progress) * (1 + 0.1 * sin(p.age * 17))
            p.node.zRotation = atan2(-p.vx, p.vy - p.gravity * p.age) * 0.65
            p.node.childNode(withName: "flameTail")?.yScale = 0.8 + 0.2 * sin(p.age * 11)
        }
        particles.removeAll { particle in
            if particle.age >= particle.life { particle.node.removeFromParent(); return true }
            return false
        }
    }
}
