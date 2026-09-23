import AppKit
import SpriteKit
import CoreText
import CoreImage
import SpiritCore

struct HammerFlightSample {
    let position: CGPoint
    let size: CGSize
    let rotation: CGFloat
    let opacity: CGFloat
}

/// Scene-coordinate handoff for the click-through, screen-space flying hammer.
struct HammerFlightFrame {
    let texture: SKTexture
    let position: CGPoint
    let size: CGSize
    let rotation: CGFloat
    let opacity: CGFloat
    let anchorPoint: CGPoint
    var trail: [HammerFlightSample] = []
}

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
    private let happyEyes = SKNode()
    private let focusedEyes = SKNode()
    private let surprisedEyes = SKNode()
    private let brows = SKNode()
    private let workSurface = SKNode()
    private let storyEmber = SKSpriteNode()
    private let smileMouth = SKNode()
    private let surprisedMouth = SKNode()
    private let worriedMouth = SKNode()
    private(set) var displayedExpression: SpiritExpression = .neutral
    private var flameParts: [SKSpriteNode] = []
    private let coreGlow = SKSpriteNode(color: .yellow, size: CGSize(width: 7, height: 9))
    private let heldEmber = SKSpriteNode(color: .yellow, size: CGSize(width: 1.4, height: 1.4))
    private var previousPointer: CGPoint?
    var remainingQuota: Double? { didSet { motion.setRemainingQuota(remainingQuota) } }
    private let hammer = SKNode()
    private let heldHammer = SKSpriteNode()
    private let chargeLightning = SKNode()
    private let skyLightning = SKNode()
    private let chargeMotes = SKNode()
    private let chargedEyes = SKNode()
    private let chargedMouth = SKNode()
    private let flyingHammer = SKSpriteNode()
    private var frontTorso: SKSpriteNode?
    private var poseTextures: [SKTexture] = []
    private let poseTorso = SKSpriteNode()
    private let poseHand = SKSpriteNode()
    private let restingHand = SKSpriteNode()
    private let foldedFreeHand = SKSpriteNode()
    private var hammerLiftDelay = 0.0
    private let hammerTrail = SKNode()
    private var flightHistory: [(time: Double, sample: HammerFlightSample)] = []
    private var hammerPartsLoaded = false
    private var hammerTrick: HammerTrick?
    private var hammerTrickTime = 0.0
    private var userTrickPending = false
    private var userTrickActive = false
    private var requestedUserTrick: HammerTrick = .toss
    private var hammerPulling = false
    private var hammerPullTarget = 0.0
    private var hammerPullAmount = 0.0
    private var savedRecallOffset: CGPoint?

    func pullHammer(progress: Double) {
        guard !isHammerTrickPlaying, !userTrickPending,
              spiritState == .idle || spiritState == .working,
              !reducedMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        hammerPulling = true
        hammerPullTarget = min(1, max(0, progress))
        motion.setState(.idle)
        motion.setIdleActionActive(true)
    }

    func releaseHammerPull() {
        guard hammerPulling else { return }
        hammerPulling = false
        motion.setIdleActionActive(false)
        if hammerPullTarget >= 1 {
            requestedUserTrick = .snatchRecall
            userTrickPending = true
            savedRecallOffset = hammerRecallOffset
            hammerRecallOffset = CGPoint(x: -110, y: 36)
        }
        hammerPullTarget = 0
        if hammerPullAmount == 0 && !userTrickPending { motion.setState(spiritState) }
    }
    var hammerTossHeightScale: CGFloat = 1
    private let originalGripOffset = CGFloat((0.385 - 0.90) * 312 * 0.047)

    func hammerContains(_ point: CGPoint) -> Bool {
        guard !heldHammer.isHidden, !isHammerTrickPlaying else { return false }
        let local = heldHammer.convert(point, from: self)
        let rect = CGRect(x: -heldHammer.anchorPoint.x * heldHammer.size.width,
                          y: -heldHammer.anchorPoint.y * heldHammer.size.height,
                          width: heldHammer.size.width, height: heldHammer.size.height)
        return rect.insetBy(dx: -3, dy: -3).contains(local)
    }

    @discardableResult
    func requestHammerToss() -> Bool {
        guard !userTrickPending, !isHammerTrickPlaying, hammerPartsLoaded,
              spiritState == .idle || spiritState == .working,
              !reducedMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return false }
        requestedUserTrick = .toss
        userTrickPending = true
        // Let the current strike finish before transferring ownership of the hammer.
        motion.setState(.idle)
        return true
    }
    private var trickCaught = false
    var automaticallyPlaysHammerTricks = true {
        didSet { motion.setAutomaticIdleActionsEnabled(automaticallyPlaysHammerTricks) }
    }
    var onHammerFlight: ((HammerFlightFrame?) -> Void)?
    var hammerRecallOffset = CGPoint(x: 140, y: 65)
    var characterScale: CGFloat { stage.xScale }
    var isHammerTrickPlaying: Bool { hammerTrick != nil }
    var canPlayHammerTrick: Bool {
        hammerPartsLoaded && !hammerPulling && hammerTrick == nil && (spiritState == .idle || userTrickPending) && !motion.isForging
            && !reducedMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            && motion.pose.charge < 0.1 && motion.canPlayIdleAction
    }
    private let freeArm = SKNode()
    private let sparks = SKNode()
    private var providerLabelVisible = false
    private var providerLabelReveal: CGFloat = 0
    private let nameplateCrop = SKCropNode()
    private let nameplateMask = SKShapeNode()

    private func advanceNameplateReveal(by delta: TimeInterval) {
        let target: CGFloat = providerLabelVisible ? 1 : 0
        if reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            providerLabelReveal = target
        } else {
            let step = CGFloat(delta / 0.18)
            providerLabelReveal = target > providerLabelReveal
                ? min(target, providerLabelReveal + step) : max(target, providerLabelReveal - step)
        }
        let progress = providerLabelReveal
        nameplateMask.xScale = progress * progress * (3 - 2 * progress)
        statusLabel.isHidden = progress == 0 && !providerLabelVisible
        statusBackground.isHidden = statusLabel.isHidden
        stateBadge.isHidden = statusLabel.isHidden || provider == nil || stateBadge.text?.isEmpty != false
    }

    func setProviderLabelVisible(_ visible: Bool) {
        guard providerLabelVisible != visible else { return }
        providerLabelVisible = visible
        advanceNameplateReveal(by: 0)
    }

    /// Anchor dialogue to the actual body, excluding the hammer, effects and nameplate.
    var speechAnchorBounds: CGRect {
        let rect = body.calculateAccumulatedFrame()
        let a = convert(rect.origin, from: stage)
        let b = convert(CGPoint(x: rect.maxX, y: rect.maxY), from: stage)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private let statusBackground = SKShapeNode()
    private let statusLabel = SKSpriteNode()
    private var identityText = ""
    var provider: SpiritProvider? { didSet { updateIdentity() } }
    var isObserved = true { didSet { updateIdentity() } }
    var displayedLabel: String { identityText }
    private let stateBadge = SKLabelNode(fontNamed: "AppleSDGothicNeo-Bold")
    func setTypingActive(_ active: Bool) { motion.setTypingActive(active) }
    private var motion = SpiritRigMotion()
    private var flameTime = 0.0
    private var chargeEmissionTime = 0.0
    private var emissionContours: [(node: SKSpriteNode, points: [CGPoint])] = []
    private var emissionOrder: [Int] = []
    private var nextChargeEmission = 0.15
    private var baseStageScale: CGFloat = 1
    var onTransform: (() -> Void)?
    var onChargeEnded: (() -> Void)?
    private var chargeSpeechActive = false

    private func finishChargeSpeechIfNeeded() {
        guard chargeSpeechActive else { return }
        chargeSpeechActive = false
        onChargeEnded?()
    }
    var effectTexture: SKTexture { flyingFlameTextures.randomElement()! }
    var effectShader: SKShader? { motion.pose.charge > 0.08 ? chargeShader : nil }
    var interactionCharge: Double { motion.pose.charge }

    @discardableResult
    func playEmberPlay() -> Bool {
        guard !reducedMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return false }
        return motion.playEmberPlay()
    }

    func cancelInteractions() {
        motion.cancelInteractions()
        finishChargeSpeechIfNeeded()
        previousPointer = nil
        cancelHammerTrick()
    }

    func beginPress() { cancelHammerTrick(); motion.beginPress() }
    @discardableResult
    func endPress(registerTap: Bool) -> Bool { motion.endPress(registerTap: registerTap) }
    func setDragVelocity(x: Double, y: Double) {
        if x != 0 || y != 0 { cancelHammerTrick() }
        let scale = max(stage.xScale, 0.5)
        motion.setDragVelocity(x: x / scale, y: y / scale)
    }

    func setDragging(_ dragging: Bool) {
        if dragging { cancelHammerTrick() }
        motion.setDragging(dragging)
    }

    func setPointer(x: Double?, y: Double?, velocityX: Double = 0, velocityY: Double = 0) {
        motion.setPointer(x: x, y: y, velocityX: velocityX, velocityY: velocityY)
        if let x, let y, x.isFinite, y.isFinite,
           abs(x) < 22, y > 32, y < 62,
           hypot(velocityX, velocityY) > 8, hypot(velocityX, velocityY) < 170,
           hammerTrick != nil { cancelHammerTrick() }
    }

    @discardableResult
    func playHammerTrick(_ trick: HammerTrick) -> Bool {
        guard canPlayHammerTrick else { return false }
        userTrickActive = userTrickPending
        userTrickPending = false
        motion.setIdleActionActive(true)
        hammerTrick = trick
        hammerLiftDelay = motion.pose.hammerRest > 0.01 ? 0.42 : 0
        hammerTrickTime = -hammerLiftDelay
        trickCaught = false
        flightHistory.removeAll()
        apply(motion.pose)
        return true
    }

    func cancelHammerTrick() {
        let restoreState = userTrickPending || userTrickActive || hammerPulling || hammerPullAmount > 0
        hammerPulling = false
        hammerPullAmount = 0
        hammerPullTarget = 0
        if let savedRecallOffset { hammerRecallOffset = savedRecallOffset }
        savedRecallOffset = nil
        userTrickPending = false
        userTrickActive = false
        motion.setIdleActionActive(false)
        if restoreState { motion.setState(spiritState) }
        hammerTrick = nil
        hammerTrickTime = 0
        heldHammer.isHidden = false
        heldHammer.alpha = 1
        flyingHammer.isHidden = true
        flightHistory.removeAll()
        for ghost in hammerTrail.children { ghost.isHidden = true }
        onHammerFlight?(nil)
        apply(motion.pose)
    }
    private var previousTime: TimeInterval?
    private var reducedMotion = false
    private static let chargeGlowColors = [
        NSColor(red: 1, green: 0.42, blue: 0.08, alpha: 1),
        NSColor(red: 1, green: 0.73, blue: 0.12, alpha: 1),
        NSColor(red: 1, green: 0.96, blue: 0.55, alpha: 1),
        NSColor(red: 0.40, green: 0.94, blue: 0.86, alpha: 1),
        NSColor(red: 0.35, green: 0.84, blue: 1, alpha: 1)
    ]
    private let chargeUniform = SKUniform(name: "u_charge", float: 0)
    // The body and flame share the same five heat stages, preserving dark pixel edges.
    private static let chargePalette = """
        vec3 chargeColor(vec3 base, float shade, float charge) {
            vec3 gold = mix(vec3(0.86, 0.28, 0.025), vec3(1.0, 0.83, 0.25), shade);
            vec3 yellow = mix(vec3(0.94, 0.49, 0.04), vec3(1.0, 0.98, 0.69), shade);
            vec3 whiteHot = mix(vec3(0.10, 0.72, 0.73), vec3(1.0, 1.0, 0.92), shade);
            vec3 blueHot = mix(vec3(0.10, 0.38, 0.94), vec3(0.88, 1.0, 1.0), shade);
            vec3 color = mix(base, gold, smoothstep(0.0, 0.23, charge));
            color = mix(color, yellow, smoothstep(0.23, 0.48, charge));
            color = mix(color, whiteHot, smoothstep(0.48, 0.75, charge));
            return mix(color, blueHot, smoothstep(0.75, 1.0, charge));
        }
        """
    private lazy var chargeShader = SKShader(source: Self.chargePalette + """
        void main() {
            vec4 source = SKDefaultShading();
            vec3 rgb = source.rgb / max(source.a, 0.001);
            float shade = rgb.g < 0.32 ? 0.0 : rgb.g < 0.65 ? 0.42 : rgb.b < 0.60 ? 0.82 : 1.0;
            vec3 color = chargeColor(rgb, shade, u_charge);
            gl_FragColor = vec4(color * source.a, source.a);
        }
        """, uniforms: [chargeUniform])
    private let flameClock = SKUniform(name: "u_flameTime", float: 0)
    private let flameEnergy = SKUniform(name: "u_flameEnergy", float: 1)
    private let flameBend = SKUniform(name: "u_flameBend", float: 0)
    private let flameLength = SKUniform(name: "u_flameLength", float: 1)
    private let flameCooling = SKUniform(name: "u_flameCooling", float: 0)
    private lazy var pixelFlameShader = SKShader(source: Self.chargePalette + """
        void main() {
            // One cell is about 1pt in the 64pt rig, half the old atlas step.
            // Quantize the OUTPUT: bending a coarse source alone cannot add detail.
            vec2 grid = vec2(42.0, 55.0);
            vec2 p = (floor(v_tex_coord * grid) + 0.5) / grid;
            // Keep the face rooted; let the crown carry most of the deformation.
            float rise = smoothstep(0.20, 0.65, p.y);
            float t = u_flameTime;
            float wave = sin(t * 3.8 - p.y * 10.0 + p.x * 3.0);
            float curl = sin(t * 6.1 - p.y * 14.0 - p.x * 7.0);
            vec2 q = p;
            q.x -= rise * (u_flameBend * 0.65
                + u_flameEnergy * (0.043 * wave + 0.018 * curl));
            // Stretch only the crown; the face stays anchored below this pivot.
            q.y = p.y - max(0.0, p.y - 0.20) * (1.0 - 1.0 / max(0.8, u_flameLength));
            q.y -= rise * u_flameEnergy * 0.018 * sin(t * 4.5 - p.y * 8.0 + p.x * 13.0);
            vec4 edge = texture2D(u_texture, q);
            float inside = step(0.48, edge.a);
            // Let the hotter color boundaries lick upward within the silhouette.
            vec2 hot = q;
            hot.x += u_flameEnergy * rise * 0.013 * sin(t * 5.0 - p.y * 13.0);
            hot.y += u_flameEnergy * rise * 0.018 * sin(t * 3.6 - p.y * 11.0 + p.x * 9.0);
            vec4 source = texture2D(u_texture, hot);
            vec3 rgb = source.rgb / max(source.a, 0.001);
            vec3 base;
            float shade;
            if (rgb.g < 0.42) {
                base = vec3(0.914, 0.263, 0.102);
                shade = 0.0;
            } else if (rgb.g < 0.73) {
                base = vec3(1.0, 0.588, 0.188);
                shade = 0.48;
            } else {
                base = vec3(1.0, 0.882, 0.439);
                shade = 1.0;
            }
            base = mix(base, vec3(0.78, 0.35, 0.12), u_flameCooling * 0.24);
            vec3 color = chargeColor(base, shade, u_charge);
            gl_FragColor = vec4(color * inside, inside) * v_color_mix.a;
        }
        """, uniforms: [flameClock, flameEnergy, flameBend, flameLength, flameCooling, chargeUniform])

    private lazy var flyingFlameTextures = (0..<3).map { makeFlyingFlameTexture(variant: $0) }
    private struct Ember {
        let node: SKSpriteNode
        var age = 0.0
        var vx: Double
        var vy: Double
        let life: Double
        let gravity: Double
        let drag: Double
        let curl: Double
        let phase: Double
        let flutter: Double
    }
    private var particles: [Ember] = []
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
        nameplateCrop.name = "providerNameplate"
        nameplateMask.name = "providerRevealMask"
        nameplateMask.fillColor = .white
        nameplateMask.strokeColor = .clear
        nameplateMask.xScale = 0
        nameplateCrop.maskNode = nameplateMask
        addChild(nameplateCrop)
        nameplateCrop.addChild(statusBackground)
        statusLabel.name = "providerLabel"
        stage.name = "stage"
        if let url = Bundle.main.url(forResource: "neodgm", withExtension: "ttf", subdirectory: "Spirit/Fonts") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        statusLabel.zPosition = 21
        nameplateCrop.addChild(statusLabel)
        stateBadge.fontSize = 11
        stateBadge.fontColor = .white
        stateBadge.zPosition = 22
        nameplateCrop.addChild(stateBadge)
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
        // Exported from the seven-layer Aseprite source in SourceArt/Spirit.
        // Crop positions stay fixed so editing the artwork preserves every pivot.
        func part(_ rect: CGRect, scale: CGFloat) -> SKSpriteNode {
            let texture = SKTexture(rect: CGRect(x: rect.minX / 1254, y: 1 - rect.maxY / 1254,
                                                width: rect.width / 1254, height: rect.height / 1254), in: atlas)
            texture.filteringMode = .nearest
            return SKSpriteNode(texture: texture, size: CGSize(width: rect.width * scale, height: rect.height * scale))
        }
        let unit: CGFloat = 48 / 672
        let torso = part(CGRect(x: 170, y: 500, width: 368, height: 230), scale: unit)
        torso.name = "frontTorso"
        frontTorso = torso
        torso.anchorPoint = CGPoint(x: 0.5, y: 0)
        torso.zPosition = 1
        body.addChild(torso)
        flameParts.append(torso)
        let headPart = part(CGRect(x: 104, y: 53, width: 495, height: 480), scale: unit)
        head.texture = headPart.texture
        head.size = headPart.size
        // Smooth the old large stairs into a contour field, then rasterize them
        // on the finer grid in the shader. Padding gives the tips room to rise.
        if let atlasImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let crop = atlasImage.cropping(to: CGRect(x: 104, y: 53, width: 495, height: 480)) {
            let field = CIImage(cgImage: crop).applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 11.0])
            let bounds = CGRect(x: -42, y: 0, width: 579, height: 760)
            if let smoothed = CIContext().createCGImage(field, from: bounds) {
                head.texture = SKTexture(cgImage: smoothed)
                head.texture?.filteringMode = .linear
                head.size = CGSize(width: bounds.width * unit, height: bounds.height * unit)
                head.shader = pixelFlameShader
            }
        }
        head.anchorPoint = CGPoint(x: 0.5, y: 0)
        head.position = CGPoint(x: 0, y: 197 * unit)
        head.zPosition = 2
        body.addChild(head)
        if head.shader == nil { flameParts.append(head) }
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
        for (name, node) in [("happyEyes", happyEyes), ("focusedEyes", focusedEyes), ("surprisedEyes", surprisedEyes)] {
            node.name = name
            eyes.addChild(node)
        }
        for (rect, x) in [(CGRect(x: 756, y: 927, width: 94, height: 127), -6.8),
                          (CGRect(x: 1026, y: 927, width: 95, height: 127), 6.8)] {
            let eye = part(rect, scale: 0.044)
            eye.position.x = x
            openEyes.addChild(eye)
        }
        // Pixel eyelids have their own geometry: no squashed pupils or highlights.
        let ink = NSColor(red: 84 / 255.0, green: 45 / 255.0, blue: 26 / 255.0, alpha: 1)
        func pixel(_ parent: SKNode, x: Double, y: Double, width: Double, height: Double,
                   color: NSColor = NSColor(red: 84 / 255.0, green: 45 / 255.0, blue: 26 / 255.0, alpha: 1)) {
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
        for x in [-6.8, 6.8] {
            // Happiness arches upward; sleepy lids curve downward.
            pixel(happyEyes, x: x, y: 0.8, width: 2.9, height: 1.0)
            pixel(happyEyes, x: x - 1.9, y: -0.1, width: 1, height: 1.2)
            pixel(happyEyes, x: x + 1.9, y: -0.1, width: 1, height: 1.2)
            pixel(focusedEyes, x: x, y: -0.4, width: 2.8, height: 2.7)
            pixel(focusedEyes, x: x, y: 1.2, width: 4.1, height: 0.9)
            pixel(focusedEyes, x: x + 0.5, y: 0, width: 0.8, height: 0.8,
                  color: NSColor(red: 1, green: 0.89, blue: 0.60, alpha: 1))
            pixel(surprisedEyes, x: x, y: 0, width: 3.5, height: 5.0)
            pixel(surprisedEyes, x: x, y: 0, width: 4.5, height: 3.1)
            pixel(surprisedEyes, x: x + 0.6, y: 1, width: 1.1, height: 1.3,
                  color: NSColor(red: 1, green: 0.93, blue: 0.73, alpha: 1))
        }
        for (name, node) in [("smileMouth", smileMouth), ("surprisedMouth", surprisedMouth), ("worriedMouth", worriedMouth)] {
            node.name = name
            node.position = CGPoint(x: 0, y: 5.1)
            node.zPosition = 2
            head.addChild(node)
        }
        pixel(smileMouth, x: 0, y: -0.7, width: 2.6, height: 0.9)
        pixel(smileMouth, x: -1.8, y: 0.1, width: 1, height: 1.2)
        pixel(smileMouth, x: 1.8, y: 0.1, width: 1, height: 1.2)
        pixel(worriedMouth, x: 0, y: 0.3, width: 2.4, height: 0.9)
        pixel(worriedMouth, x: -1.6, y: -0.5, width: 0.9, height: 1)
        pixel(worriedMouth, x: 1.6, y: -0.5, width: 0.9, height: 1)
        pixel(surprisedMouth, x: 0, y: 0, width: 2.2, height: 3.0)
        pixel(surprisedMouth, x: 0, y: 0, width: 3.4, height: 1.4)
        let mouthPart = part(CGRect(x: 886, y: 1035, width: 108, height: 42), scale: 0.044)
        mouth.texture = mouthPart.texture
        mouth.size = mouthPart.size
        mouth.position = CGPoint(x: 0, y: 5.1)
        mouth.zPosition = 2
        head.addChild(mouth)
        // Shoulder pivot at the right end, not the centre of the hammer image.
        let toolSize = CGSize(width: 312 * 0.047, height: 396 * 0.047)
        if let partsURL = Bundle.main.url(forResource: "hammer-parts", withExtension: "png", subdirectory: "Spirit"),
           let partsImage = NSImage(contentsOf: partsURL) {
            let parts = SKTexture(image: partsImage)
            parts.filteringMode = .nearest
            heldHammer.texture = SKTexture(rect: CGRect(x: 0, y: 0, width: 0.5, height: 1), in: parts)
            heldHammer.texture?.filteringMode = .nearest
            heldHammer.size = toolSize
            heldHammer.name = "heldHammer"
            // The grip stays fixed when ownership passes from the hand to the flying node.
            heldHammer.anchorPoint = CGPoint(x: 0.385, y: 0.25)
            heldHammer.position.x = (0.385 - 0.90) * toolSize.width
            hammer.addChild(heldHammer)
            chargeLightning.name = "chargeLightning"
            chargeLightning.zPosition = 3
            heldHammer.addChild(chargeLightning)
            for _ in 0..<9 {
                let bolt = SKShapeNode()
                bolt.strokeColor = NSColor(calibratedRed: 0.62, green: 0.92, blue: 1, alpha: 1)
                bolt.lineWidth = 0.8
                bolt.glowWidth = 0.45
                bolt.isAntialiased = false
                chargeLightning.addChild(bolt)
            }
            let hand = SKSpriteNode(texture: SKTexture(rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1), in: parts), size: toolSize)
            hand.texture?.filteringMode = .nearest
            hand.name = "hammerHand"
            hand.anchorPoint = CGPoint(x: 0.90, y: 0.25)
            hand.zPosition = 1
            hammer.addChild(hand)
            flameParts.append(hand)
            if let url = Bundle.main.url(forResource: "hero-hammer", withExtension: "png", subdirectory: "Spirit"),
               let image = NSImage(contentsOf: url) {
                heldHammer.texture = SKTexture(image: image)
                heldHammer.texture?.filteringMode = .nearest
                heldHammer.size = CGSize(width: 18, height: 27)
                heldHammer.anchorPoint = CGPoint(x: 0.5, y: 0.3125)
            }
            flyingHammer.texture = heldHammer.texture
            flyingHammer.size = heldHammer.size
            flyingHammer.anchorPoint = heldHammer.anchorPoint
            flyingHammer.name = "flyingHammer"
            flyingHammer.zPosition = 8
            flyingHammer.isHidden = true
            stage.addChild(flyingHammer)
            hammerPartsLoaded = true
        } else {
            let tool = part(CGRect(x: 807, y: 255, width: 312, height: 396), scale: 0.047)
            tool.anchorPoint = CGPoint(x: 0.90, y: 0.25)
            hammer.addChild(tool)
        }
        if let url = Bundle.main.url(forResource: "hammer-keyposes", withExtension: "png", subdirectory: "Spirit"),
           let image = NSImage(contentsOf: url) {
            let sheet = SKTexture(image: image)
            sheet.filteringMode = .nearest
            poseTextures = (0..<5).map { index in
                let texture = SKTexture(rect: CGRect(x: Double(index) / 5, y: 0, width: 0.2, height: 1), in: sheet)
                texture.filteringMode = .nearest
                return texture
            }
            poseTorso.name = "hammerPoseTorso"
            poseTorso.size = CGSize(width: 32, height: 32)
            poseTorso.anchorPoint = CGPoint(x: 0.5, y: 0)
            poseTorso.zPosition = 1
            poseTorso.alpha = 0
            body.addChild(poseTorso)
            poseHand.name = "hammerPoseHand"
            poseHand.size = CGSize(width: 32, height: 32)
            poseHand.anchorPoint = CGPoint(x: 0, y: 0.5)
            poseHand.zPosition = 4.2
            poseHand.isHidden = true
            stage.addChild(poseHand)
            restingHand.name = "restingHammerHand"
            restingHand.texture = poseTextures[4]
            restingHand.size = CGSize(width: 32, height: 32)
            restingHand.anchorPoint = CGPoint(x: 0, y: 0.5)
            restingHand.zPosition = 4.2
            restingHand.isHidden = true
            stage.addChild(restingHand)
            foldedFreeHand.name = "foldedFreeHand"
            foldedFreeHand.texture = poseTextures[4]
            foldedFreeHand.size = CGSize(width: 32, height: 32)
            foldedFreeHand.anchorPoint = CGPoint(x: 0, y: 0.5)
            foldedFreeHand.zPosition = 4.3
            foldedFreeHand.isHidden = true
            stage.addChild(foldedFreeHand)
            flameParts.append(contentsOf: [poseTorso, poseHand, restingHand, foldedFreeHand])
        }
        hammerTrail.name = "hammerMotionTrail"
        hammerTrail.zPosition = 7
        for index in 0..<3 {
            let ghost = SKSpriteNode()
            ghost.name = "hammerGhost\(index)"
            ghost.anchorPoint = heldHammer.anchorPoint
            ghost.zPosition = -CGFloat(index)
            ghost.isHidden = true
            hammerTrail.addChild(ghost)
        }
        stage.addChild(hammerTrail)
        hammer.position = CGPoint(x: -9, y: 11.5)
        hammer.zPosition = 4
        stage.addChild(hammer)
        let arm = part(CGRect(x: 245, y: 892, width: 213, height: 233), scale: 0.039)
        arm.anchorPoint = CGPoint(x: 0.16, y: 0.89)
        freeArm.addChild(arm)
        flameParts.append(arm)
        freeArm.position = CGPoint(x: 9.4, y: 12.2)
        freeArm.zPosition = 3
        body.addChild(freeArm)
        // Sample the actual alpha edges once, then follow the moving part's transform.
        // Shuffled regions prevent fixed jets while still letting the whole body shed embers.
        cacheEmissionContour(torso)
        cacheEmissionContour(arm)
        cacheEmissionContour(head, bands: 3)
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
        heldEmber.position = CGPoint(x: 4.5, y: -6)
        freeArm.addChild(heldEmber)
        heldEmber.alpha = 0
        workSurface.name = "workSurface"
        workSurface.zPosition = -1
        pixel(workSurface, x: -22.7, y: -3.5, width: 6, height: 4,
              color: NSColor(calibratedWhite: 0.30, alpha: 1))
        pixel(workSurface, x: -23.5, y: -1.5, width: 10, height: 1.5,
              color: NSColor(calibratedWhite: 0.55, alpha: 1))
        pixel(workSurface, x: -22.7, y: -0.5, width: 4, height: 1,
              color: NSColor(red: 0.98, green: 0.67, blue: 0.28, alpha: 1))
        stage.addChild(workSurface)
        storyEmber.name = "storyEmber"
        storyEmber.texture = flyingFlameTextures[0]
        storyEmber.size = CGSize(width: 2.4, height: 3.2)
        storyEmber.zPosition = 5
        stage.addChild(storyEmber)
        chargedEyes.name = "chargedEyes"
        eyes.addChild(chargedEyes)
        for x in [-6.8, 6.8] {
            pixel(chargedEyes, x: x, y: 0, width: 4, height: 3.2)
            pixel(chargedEyes, x: x - 0.4, y: 0.5, width: 1.5, height: 1.7,
                  color: NSColor(red: 0.68, green: 0.95, blue: 1, alpha: 1))
        }
        chargedMouth.name = "chargedMouth"
        chargedMouth.position = CGPoint(x: 0, y: 5.1)
        chargedMouth.zPosition = 2
        head.addChild(chargedMouth)
        pixel(chargedMouth, x: 0, y: 0, width: 4.8, height: 2.7)
        pixel(chargedMouth, x: 0, y: 0.35, width: 3.1, height: 0.9,
              color: NSColor(red: 1, green: 0.95, blue: 0.82, alpha: 1))
        skyLightning.name = "skyLightning"
        skyLightning.zPosition = 7
        stage.addChild(skyLightning)
        for index in 0..<7 {
            let bolt = SKShapeNode()
            bolt.name = "skyBolt\(index)"
            bolt.strokeColor = index == 0
                ? NSColor(red: 0.25, green: 0.68, blue: 1, alpha: 1)
                : NSColor(red: 0.80, green: 0.97, blue: 1, alpha: 1)
            bolt.lineWidth = index == 0 ? 4.0 : (index == 1 ? 1.3 : 0.8)
            bolt.glowWidth = index == 0 ? 1.8 : 0
            bolt.isAntialiased = false
            skyLightning.addChild(bolt)
        }
        chargeMotes.name = "chargeMotes"
        chargeMotes.zPosition = 6
        stage.addChild(chargeMotes)
        for _ in 0..<16 {
            let mote = SKSpriteNode(color: NSColor(red: 0.64, green: 0.91, blue: 1, alpha: 1),
                                    size: CGSize(width: 0.8, height: 1.5))
            chargeMotes.addChild(mote)
        }
        brows.name = "expressionBrows"
        eyes.addChild(brows)
        pixel(brows, x: -6.8, y: 4, width: 4, height: 0.9)
        pixel(brows, x: 6.8, y: 4, width: 4, height: 0.9)
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
        // Reserve headroom for the lifted silhouette and the completion hop.
        baseStageScale = min(side / 64, (side - stage.position.y) / 62)
        stage.setScale(baseStageScale)
        stateBadge.position = CGPoint(x: statusLabel.position.x + image.size.width / 2 + 9,
                                      y: statusLabel.position.y - 4)
        updateStatusBackground()
    }

    private func updateStatusBackground() {
        let labelSize = statusLabel.frame.size
        let badgeWidth: CGFloat = provider == nil || stateBadge.text?.isEmpty != false ? 0 : 17
        statusBackground.path = CGPath(roundedRect: CGRect(
            x: -(labelSize.width + 16) / 2, y: -(labelSize.height + 7) / 2,
            width: labelSize.width + 16 + badgeWidth, height: labelSize.height + 7
        ), cornerWidth: 0, cornerHeight: 0, transform: nil)
        let bounds = statusBackground.frame
        nameplateMask.position = CGPoint(x: bounds.midX, y: bounds.midY)
        nameplateMask.path = CGPath(rect: CGRect(x: -bounds.width / 2 - 1, y: -bounds.height / 2 - 1,
                                               width: bounds.width + 2, height: bounds.height + 2), transform: nil)
    }

    func render(state: SpiritState, reduceMotion: Bool) {
        let userPlaying = userTrickPending || userTrickActive || hammerPulling || hammerPullAmount > 0
        if reduceMotion || (state != .idle && !(state == .working && userPlaying)) { cancelHammerTrick() }
        spiritState = state
        updateIdentity()
        motion.setState((userTrickPending || userTrickActive || hammerPulling || hammerPullAmount > 0) ? .idle : state)
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
        advanceNameplateReveal(by: 0)
        updateStatusTexture()
    }

    override func update(_ currentTime: TimeInterval) {
        let delta = previousTime.map { min(max(currentTime - $0, 0), 1.0 / 15) } ?? 0
        previousTime = currentTime
        advanceNameplateReveal(by: delta)
        // Match the motion engine's resume clamp so particles never run ahead of the rig.
        let elapsed = min(delta * min(max(playbackRate, 0.25), 1.5), 1.0 / 20)
        if tracksPointer && !reducedMotion, let view, let window = view.window {
            let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            let scenePoint = convertPoint(fromView: view.convert(windowPoint, from: nil))
            let point = stage.convert(scenePoint, from: self)
            let velocity = previousPointer.map { CGPoint(x: (point.x - $0.x) / max(delta, 0.001),
                                                        y: (point.y - $0.y) / max(delta, 0.001)) } ?? .zero
            setPointer(x: point.x, y: point.y, velocityX: velocity.x, velocityY: velocity.y)
            previousPointer = point
        }
        if !reducedMotion { flameTime += elapsed }
        let wasPulling = hammerPullAmount > 0
        hammerPullAmount += (hammerPullTarget - hammerPullAmount) * min(1, elapsed / 0.06)
        if hammerPullAmount < 0.005 { hammerPullAmount = 0 }
        if wasPulling && hammerPullAmount == 0 && !hammerPulling && !userTrickPending && !userTrickActive {
            motion.setState(spiritState)
        }
        var pose = motion.advance(by: elapsed, reduceMotion: reducedMotion)
        if userTrickPending && canPlayHammerTrick { _ = playHammerTrick(requestedUserTrick) }
        if !motion.isForging && hammerPullAmount > 0 {
            pose.bodyAngle += 0.09 * hammerPullAmount
            pose.bodyOffsetY -= 0.4 * hammerPullAmount
            pose.headAngle -= 0.055 * hammerPullAmount
            pose.gazeX -= 1.2 * hammerPullAmount
            pose.freeArmAngle -= 0.12 * hammerPullAmount
        }
        if let trick = hammerTrick {
            hammerTrickTime += elapsed
            if hammerTrickTime >= trick.duration {
                cancelHammerTrick()
                pose = motion.advance(by: 0, reduceMotion: reducedMotion)
            }
        } else if pose.didRequestHammerTrick && automaticallyPlaysHammerTricks {
            _ = playHammerTrick(.toss)
        }
        if userTrickActive, let trick = hammerTrick, hammerTrickTime > trick.catchTime + 0.12 {
            pose.expression = .proud
        }
        apply(pose)
        if !reducedMotion {
            if pose.didTransform {
                chargeSpeechActive = true
                onTransform?()
                emitEmbers(count: 14, celebration: true, heat: 1)
            }
            chargeEmissionTime += elapsed
            if pose.charge > 0.1 && chargeEmissionTime > nextChargeEmission {
                emitEmbers(count: Int.random(in: 1...3), celebration: false, heat: 1)
                chargeEmissionTime = 0
                nextChargeEmission = Double.random(in: 0.09...0.24)
            }
            if pose.didStrike && pose.charge < 0.12 { emitSparks(strength: pose.strikeStrength) }
            if pose.didCelebrate { emitEmbers(count: 16, celebration: true, heat: pose.heat) }
            if pose.didEmitEmber {
                emitEmbers(count: spiritState == .working ? Int.random(in: 1...3) : 1,
                           celebration: false, heat: pose.heat)
            }
        }
        if pose.charge < 0.08 || reducedMotion { finishChargeSpeechIfNeeded() }
        updateSparks(by: elapsed)
    }

    private func apply(_ pose: SpiritRigPose) {
        stage.setScale(baseStageScale)
        body.position.x = 0
        frontTorso?.alpha = 1
        poseTorso.alpha = 0
        poseHand.isHidden = true
        restingHand.isHidden = true
        foldedFreeHand.isHidden = true
        freeArm.alpha = 1
        for ghost in hammerTrail.children { ghost.isHidden = true }
        hammer.childNode(withName: "hammerHand")?.isHidden = false
        hammer.childNode(withName: "hammerHand")?.alpha = 1
        heldHammer.position = CGPoint(x: originalGripOffset, y: 0)
        heldHammer.anchorPoint = CGPoint(x: 0.5, y: 0.3125)
        freeArm.position.x = 9.4
        freeArm.xScale = 1
        freeArm.zPosition = 3
        eyes.xScale = 1
        mouth.position.x = 0
        smileMouth.position.x = 0
        head.position.x = 0
        head.xScale = 1
        body.position.y = pose.bodyOffsetY
        body.yScale = pose.bodyScaleY
        body.xScale = pose.bodyScaleX
        body.zRotation = pose.bodyAngle
        head.zRotation = pose.headAngle
        head.position.y = 197 * (48.0 / 672) - pose.restAmount * 0.45
        hammer.position = body.convert(CGPoint(x: -9, y: 11.5 - pose.restAmount * 1.2), to: stage)
        freeArm.position.y = 12.2 - pose.restAmount * 0.7
        hammer.zRotation = body.zRotation + pose.hammerAngle
        freeArm.zRotation = pose.freeArmAngle
        eyes.yScale = 1
        displayedExpression = pose.expression
        let happy = pose.expression == .content || pose.expression == .proud
        let closed = !happy && (pose.eyeOpen < 0.25 || pose.expression == .sleeping)
        let tired = !closed && !happy && pose.expression == .tired
        let focused = !closed && pose.expression == .focused
        let surprised = !closed && pose.expression == .surprised
        let yawning = pose.expression == .yawning
        brows.isHidden = ![SpiritExpression.curious, .requesting, .worried].contains(pose.expression)
        for (index, brow) in brows.children.enumerated() {
            let direction: CGFloat = index == 0 ? 1 : -1
            brow.zRotation = pose.expression == .worried ? direction * 0.3 : direction * -0.18
            brow.position.y = pose.expression == .curious && index == 1 ? 5 : 4
        }
        openEyes.isHidden = closed || tired || happy || focused || surprised
        tiredEyes.isHidden = !tired
        closedEyes.isHidden = !closed
        happyEyes.isHidden = !happy
        focusedEyes.isHidden = !focused
        surprisedEyes.isHidden = !surprised
        worriedMouth.isHidden = pose.expression != .worried
        mouth.isHidden = happy || surprised || yawning || pose.expression == .worried
        smileMouth.isHidden = !happy
        surprisedMouth.isHidden = !surprised && !yawning
        surprisedMouth.yScale = yawning ? 1.4 : 1
        // Reopen one eye slightly ahead of the other after stroking.
        let reopening = happy && pose.eyeReopen > 0 && pose.eyeReopen < 1
        if reopening { openEyes.isHidden = false }
        for eye in openEyes.children {
            eye.xScale = 1
            eye.isHidden = reopening && pose.eyeReopen < (eye.position.x < 0 ? 0.35 : 0.65)
        }
        for lid in happyEyes.children {
            lid.isHidden = reopening && pose.eyeReopen >= (lid.position.x < 0 ? 0.35 : 0.65)
        }
        mouth.yScale = pose.mouthOpen
        eyes.position.x = pose.gazeX
        eyes.position.y = 9.1 + pose.gazeY
        chargeUniform.floatValue = Float(pose.charge)
        let glowPosition = min(3.999, max(0, pose.charge) * 4)
        let glowIndex = Int(glowPosition)
        let powerColor = Self.chargeGlowColors[glowIndex].blended(
            withFraction: glowPosition - Double(glowIndex), of: Self.chargeGlowColors[glowIndex + 1])!
        aura.color = powerColor
        aura.position = head.position
        aura.zRotation = head.zRotation
        aura.setScale(1 + pose.charge * 0.20)
        aura.alpha = pose.charge * (0.30 + 0.07 * sin(flameTime * 5))
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
        workSurface.alpha = pose.workSurface
        storyEmber.alpha = pose.playEmberOpacity
        storyEmber.position = CGPoint(x: pose.playEmberX, y: pose.playEmberY)
        heldEmber.alpha = pose.heldEmber
        heldEmber.setScale(0.6 + pose.heldEmber * 0.4)
        flameClock.floatValue = Float(flameTime)
        flameEnergy.floatValue = reducedMotion ? 0
            : Float((0.55 + 0.45 * pose.vitality) * (1 - 0.65 * pose.restAmount))
        flameBend.floatValue = Float(pose.flameSway)
        flameLength.floatValue = Float(pose.flameStretch + 0.035 * pow(pose.charge, 4) * sin(flameTime * 5))
        flameCooling.floatValue = Float(cooling)
        applyGroundedHammer(pose)
        applyChargingHammer(pose)
        applyHammerTrick()
    }

    private func applyChargingHammer(_ pose: SpiritRigPose) {
        chargeLightning.isHidden = true
        skyLightning.isHidden = true
        chargeMotes.isHidden = true
        chargedEyes.isHidden = true
        chargedMouth.isHidden = true
        let amount = min(1, max(0, (pose.charge - 0.12) / 0.70))
        guard amount > 0, pose.hammerRest < 0.001, hammerTrick == nil, !reducedMotion else { return }
        let lift = CGFloat(amount * amount * (3 - 2 * amount))
        // A slow strike envelope gives the gathering energy a readable impact beat.
        let cycle = flameTime / 0.82
        let beat = cycle - floor(cycle)
        let impact = pow(max(0, 1 - abs(beat - 0.24) / 0.15), 2) * amount
        body.position.y -= impact * 0.65
        head.zRotation -= impact * 0.045
        body.position.x -= 2.2 * lift
        body.zRotation -= 0.14 * lift
        body.yScale *= 1 - 0.025 * lift
        head.zRotation += 0.045 * lift
        eyes.position.y += 0.6 * lift
        freeArm.zRotation -= 0.32 * lift
        workSurface.alpha *= 1 - lift
        let shoulder = body.convert(CGPoint(x: -9, y: 12), to: stage)
        let armAngle = body.zRotation - 0.65 * lift
        let raisedGrip = CGPoint(x: shoulder.x - 9 * cos(armAngle) - 2 * sin(armAngle),
                                 y: shoulder.y - 9 * sin(armAngle) + 2 * cos(armAngle))
        let originalGrip = hammer.convert(heldHammer.position, to: stage)
        let grip = CGPoint(x: originalGrip.x + (raisedGrip.x - originalGrip.x) * lift,
                           y: originalGrip.y + (raisedGrip.y - originalGrip.y) * lift)
        hammer.zRotation += (0.45 - hammer.zRotation) * lift
        hammer.position = CGPoint(x: grip.x - originalGripOffset * cos(hammer.zRotation),
                                  y: grip.y - originalGripOffset * sin(hammer.zRotation))
        restingHand.isHidden = false
        restingHand.alpha = lift
        restingHand.xScale = -1
        restingHand.yScale = 1
        restingHand.zRotation = armAngle
        restingHand.position = CGPoint(x: grip.x + 9 * cos(armAngle) + 2 * sin(armAngle),
                                        y: grip.y + 9 * sin(armAngle) - 2 * cos(armAngle))
        hammer.childNode(withName: "hammerHand")?.alpha = 1 - lift
        hammer.childNode(withName: "hammerHand")?.isHidden = lift >= 1
        // Look up first, then brace against the incoming charge.
        openEyes.isHidden = true
        tiredEyes.isHidden = true
        closedEyes.isHidden = true
        happyEyes.isHidden = true
        surprisedEyes.isHidden = amount >= 0.40
        focusedEyes.isHidden = amount < 0.40 || amount > 0.78
        chargedEyes.isHidden = amount <= 0.78
        displayedExpression = amount < 0.40 ? .surprised : .focused
        brows.isHidden = amount < 0.40
        for (index, brow) in brows.children.enumerated() {
            brow.zRotation = (index == 0 ? -1 : 1) * (0.18 + 0.22 * lift)
            brow.position.y = 3.8 - impact * 0.3
        }
        eyes.position.x = -0.9 * lift
        eyes.position.y = 9.1 + 1.0 * lift - impact * 0.25
        mouth.isHidden = true
        smileMouth.isHidden = true
        worriedMouth.isHidden = true
        surprisedMouth.isHidden = amount >= 0.55
        surprisedMouth.yScale = 0.8 + impact * 0.3
        chargedMouth.isHidden = amount < 0.55
        chargedMouth.yScale = 1 + impact * 0.18
        guard amount > 0.2 else { return }
        chargeLightning.isHidden = false
        let phase = Int(flameTime * 12)
        // Keep the enlarged arcs inside the transparent character window at every size.
        func confinedToWindow(_ point: CGPoint) -> CGPoint {
            let screen = heldHammer.convert(point, to: self)
            let inset = 2.5 * characterScale
            return heldHammer.convert(CGPoint(x: min(size.width - inset, max(inset, screen.x)),
                                               y: min(size.height - inset, max(inset, screen.y))), from: self)
        }
        for (index, child) in chargeLightning.children.enumerated() {
            guard let bolt = child as? SKShapeNode else { continue }
            let path = CGMutablePath()
            let angle = Double(index % 3) * .pi * 2 / 3 + Double(phase % 17) * 0.18
            let radius = 8 + amount * 9 + impact * 2
            if index < 3 {
                // Three broken rings surround the head without obscuring its silhouette.
                path.addLines(between: (0...8).map { step in
                    let a = angle + Double(step) * 0.22
                    let r = radius + (step.isMultiple(of: 2) ? -1.2 : 1.2)
                    return confinedToWindow(CGPoint(x: cos(a) * r, y: 15 + sin(a) * r * 0.72))
                })
            } else {
                let a = angle + Double(index / 3) * 0.72
                path.addLines(between: (0...4).map { step in
                    let r = radius * 0.72 + Double(step) * (1 + amount * 1.5)
                    let zigzag = step == 0 || step == 4 ? 0 : (step.isMultiple(of: 2) ? -2.0 : 2.0)
                    return confinedToWindow(CGPoint(x: cos(a) * r - sin(a) * zigzag,
                                   y: 15 + sin(a) * r * 0.72 + cos(a) * zigzag))
                })
            }
            bolt.path = path
            bolt.lineWidth = index < 3 ? 0.65 + amount * 0.65 : 0.6 + amount * 0.35
            bolt.glowWidth = amount * 0.9
            bolt.alpha = index < 3 ? amount * (0.65 + impact * 0.35)
                : max(0, (amount - 0.45) / 0.55) * (0.45 + impact * 0.55)
        }
        skyLightning.isHidden = false
        chargeMotes.isHidden = false
        // Stage coordinates keep lightning vertical while the hammer rotates below it.
        let target = heldHammer.convert(CGPoint(x: 0, y: 17), to: stage)
        let upperLeft = stage.convert(CGPoint(x: 5, y: size.height - 4), from: self)
        let upperRight = stage.convert(CGPoint(x: size.width - 5, y: size.height - 4), from: self)
        let strike = Int(floor(cycle))
        let sourceX = min(upperRight.x - 4, max(upperLeft.x + 4,
            target.x + sin(Double(strike) * 2.4) * 8))
        let source = CGPoint(x: sourceX, y: max(target.y + 8, upperLeft.y))
        let reach = min(1, beat / 0.20)
        var route = [source]
        for step in 1...7 {
            let t = Double(step) / 7
            let jitter = step == 7 ? 0 : sin(Double(step * 13 + strike * 7)) * (2 + amount * 2)
            route.append(CGPoint(x: min(upperRight.x, max(upperLeft.x,
                source.x + (target.x - source.x) * t + jitter)),
                                 y: source.y + (target.y - source.y) * t))
        }
        func descendingPath(_ points: [CGPoint], progress: Double) -> CGPath {
            let path = CGMutablePath()
            path.move(to: points[0])
            let traveled = progress * Double(points.count - 1)
            for index in 1..<points.count {
                let fraction = min(1, max(0, traveled - Double(index - 1)))
                guard fraction > 0 else { break }
                let a = points[index - 1], b = points[index]
                path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * fraction,
                                        y: a.y + (b.y - a.y) * fraction))
            }
            return path
        }
        for (index, child) in skyLightning.children.enumerated() {
            guard let bolt = child as? SKShapeNode else { continue }
            if index < 2 {
                bolt.path = descendingPath(route, progress: reach)
                bolt.alpha = amount * (index == 0 ? 0.48 : 0.90) * (0.65 + impact * 1.0)
            } else if index < 6 {
                let side = index.isMultiple(of: 2) ? -1.0 : 1.0
                let fork = route[index]
                let origin = CGPoint(x: min(upperRight.x, max(upperLeft.x, fork.x + side * (6 + amount * 8))),
                                     y: min(source.y, fork.y + 7))
                bolt.path = descendingPath([origin, CGPoint(x: origin.x - side * 3, y: origin.y - 4),
                    CGPoint(x: fork.x + side * 2, y: fork.y + 2), fork], progress: reach)
                bolt.alpha = max(0, amount - 0.35) * (0.25 + impact * 0.75)
            } else {
                let path = CGMutablePath()
                for ray in 0..<10 {
                    let angle = Double(ray) * .pi / 5 + 0.2
                    path.move(to: CGPoint(x: target.x + cos(angle) * 2, y: target.y + sin(angle) * 2))
                    path.addLine(to: CGPoint(x: target.x + cos(angle) * (5 + impact * 9),
                                            y: target.y + sin(angle) * (5 + impact * 9)))
                }
                bolt.path = path
                bolt.alpha = impact * 0.85
            }
        }
        for (index, mote) in chargeMotes.children.enumerated() {
            let t = (flameTime * 0.85 + Double(index) / Double(chargeMotes.children.count)).truncatingRemainder(dividingBy: 1)
            let side = index % 2 == 0 ? -1.0 : 1.0
            mote.position = CGPoint(x: target.x + side * (1 - t) * (12 + amount * 6 + sin(t * .pi) * 7),
                                    y: target.y + (1 - t) * (18 + Double(index % 4) * 5))
            let scenePoint = stage.convert(mote.position, to: self)
            mote.position = stage.convert(CGPoint(x: min(size.width - 4, max(4, scenePoint.x)),
                                                  y: min(size.height - 4, max(4, scenePoint.y))), from: self)
            mote.alpha = sin(t * .pi) * amount * 0.75
            mote.zRotation = side * (1 - t) * 0.6
        }
    }

    private func applyGroundedHammer(_ pose: SpiritRigPose) {
        let rest = CGFloat(pose.hammerRest)
        guard rest > 0, !poseTextures.isEmpty, hammerTrick == nil || hammerTrickTime < 0 else { return }
        // Unfold the forearms first while the head remains flat on the ground;
        // only then pick up the handle. Reverse that order when setting it down.
        let liftPhase = min(1, rest / 0.65)
        let blend = liftPhase * liftPhase * (3 - 2 * liftPhase)
        let leanPhase = max(0, (rest - 0.65) / 0.35)
        let lean = leanPhase * leanPhase * (3 - 2 * leanPhase)
        let normalGrip = hammer.convert(heldHammer.position, to: stage)
        let floorAngle = CGFloat.pi
        heldHammer.anchorPoint.y = 0.3125 + (0.45 - 0.3125) * blend
        // The broad top face of the upside-down head is the contact surface.
        // Two transparent pixel rows in the 48px asset must not create a floor gap.
        let headTop = heldHammer.size.height * (46.0 / 48.0 - heldHammer.anchorPoint.y)
        let floorGrip = CGPoint(x: -17, y: headTop - 0.5)
        let grip = CGPoint(x: normalGrip.x + (floorGrip.x - normalGrip.x) * blend,
                           y: normalGrip.y + (floorGrip.y - normalGrip.y) * blend)
        hammer.zRotation += (floorAngle - hammer.zRotation) * blend
        let local = heldHammer.position
        hammer.position = CGPoint(x: grip.x - local.x * cos(hammer.zRotation) + local.y * sin(hammer.zRotation),
                                  y: grip.y - local.x * sin(hammer.zRotation) - local.y * cos(hammer.zRotation))
        // Fold short forearms across the belly. Unfold below the shoulder,
        // then grasp the lower handle before the hammer leaves the floor.
        let visibility = min(1, rest * 5)
        restingHand.isHidden = false
        restingHand.alpha = visibility
        restingHand.xScale = -1
        restingHand.yScale = 1
        restingHand.zRotation = .pi * lean + body.zRotation
        let graspAngle = body.zRotation
        let palm = CGPoint(x: -9 * cos(graspAngle) - 2 * sin(graspAngle),
                           y: -9 * sin(graspAngle) + 2 * cos(graspAngle))
        let graspShoulder = CGPoint(x: grip.x - palm.x, y: grip.y - palm.y)
        let foldedShoulder = body.convert(CGPoint(x: -9, y: 12), to: stage)
        restingHand.position = CGPoint(x: graspShoulder.x * (1 - lean) + foldedShoulder.x * lean,
                                        y: graspShoulder.y * (1 - lean) + foldedShoulder.y * lean)
        foldedFreeHand.isHidden = lean == 0
        foldedFreeHand.alpha = lean
        foldedFreeHand.xScale = -1
        foldedFreeHand.yScale = 1
        foldedFreeHand.zRotation = body.zRotation
        foldedFreeHand.position = body.convert(CGPoint(x: 9, y: 11.5), to: stage)
        freeArm.alpha = 1 - lean
        hammer.childNode(withName: "hammerHand")?.alpha = 1 - visibility
        hammer.childNode(withName: "hammerHand")?.isHidden = visibility >= 1
    }

    private func applyHammerTrick() {
        guard let trick = hammerTrick, hammerTrickTime >= 0 else { return }
        let pose = trick.pose(at: hammerTrickTime)
        let direction: CGFloat = trick != .toss && hammerRecallOffset.x < 0 ? -1 : 1
        body.position.x += pose.bodyOffsetX * direction
        body.position.y += pose.bodyOffsetY
        body.yScale *= pose.bodyScaleY
        body.xScale /= sqrt(pose.bodyScaleY)
        body.zRotation += pose.bodyAngle * direction
        head.position.x += pose.headOffsetX * direction
        head.position.y += pose.headOffsetY
        head.xScale = pose.headScaleX
        head.zRotation += pose.headAngle * direction
        freeArm.zRotation += pose.freeArmAngle
        hammer.position = body.convert(CGPoint(x: -9, y: 11.5 - motion.pose.restAmount * 1.2), to: stage)
        hammer.zRotation = body.zRotation + motion.pose.hammerAngle + pose.handAngle

        if trick != .toss && poseTextures.count == 5 {
            let turn = CGFloat(pose.turnAmount)
            // Authored profiles move the belly and planted feet as the torso turns.
            let catching = hammerTrickTime >= trick.catchTime && hammerTrickTime < trick.catchTime + 0.24
            poseTorso.texture = poseTextures[catching ? 2 : turn > 0.7 ? 1 : 0]
            poseTorso.xScale = direction
            // Pixel key poses switch cleanly; crossfades create ghost feet and bellies.
            poseTorso.alpha = turn >= 0.35 ? 1 : 0
            frontTorso?.alpha = 1 - poseTorso.alpha
            eyes.xScale = 1 - turn * 0.18
            for eye in openEyes.children {
                eye.xScale = eye.position.x * direction < 0 ? 1 - turn * 0.25 : 1
            }
            eyes.position.x += turn * 2.2 * direction
            mouth.position.x = turn * 2.2 * direction
            smileMouth.position.x = mouth.position.x
            // The short arm is a 1:1 drawing. Its grip stays nine units from its shoulder.
            poseHand.texture = poseTextures[hammerTrickTime < trick.catchTime ? 3 : 4]
            let returning = hammerTrickTime > trick.catchTime
            let handVisibility = returning || trick == .snatchRecall ? min(1, turn * 10)
                : min(1, max(0, (hammerTrickTime - trick.releaseTime + 0.12) / 0.12))
            poseHand.isHidden = handVisibility == 0
            poseHand.alpha = handVisibility
            poseHand.xScale = direction
            poseHand.yScale = 1
            // At the end the same rigid arm folds back to the original left-hand grip.
            let oldGripX = -9 + originalGripOffset
            let restingShoulderX = oldGripX + hypot(9, 2)
            let shoulderX = returning ? restingShoulderX * (1 - turn) + 8 * direction * turn : 8 * direction
            poseHand.position = body.convert(CGPoint(x: shoulderX, y: 11.5), to: stage)
            let restingAngle: CGFloat = direction > 0 ? .pi - atan2(2, 9) : atan2(2, 9)
            let reachingAngle = direction * (0.08 + 0.24 * pose.reachAmount)
            poseHand.zRotation = (returning ? restingAngle * (1 - turn) + reachingAngle * turn : reachingAngle)
                + body.zRotation
            freeArm.position.x = 9.4 * (1 - turn) - 8 * direction * turn
            freeArm.xScale = direction > 0 && turn > 0.5 ? -1 : 1
            freeArm.zPosition = turn > 0.05 ? 0.5 : 3
            hammer.childNode(withName: "hammerHand")?.alpha = 1 - handVisibility
            hammer.childNode(withName: "hammerHand")?.isHidden = handVisibility >= 1
            // Switch tool ownership while it is invisible; fold back before restoring the old rig.
            if hammerTrickTime >= trick.releaseTime && turn > 0.00001 {
                let grip = poseHand.convert(CGPoint(x: 9, y: 2), to: stage)
                hammer.zRotation = direction * pose.handAngle * 0.3 * turn + (motion.pose.hammerAngle + pose.handAngle) * (1 - turn) + body.zRotation
                // Preserve the original shoulder-to-grip offset while both hand drawings blend.
                // Moving the parent to the grip would offset the returning original hand by 7.55 units.
                let localGrip = heldHammer.position
                let rotatedGrip = CGPoint(x: localGrip.x * cos(hammer.zRotation) - localGrip.y * sin(hammer.zRotation),
                                          y: localGrip.x * sin(hammer.zRotation) + localGrip.y * cos(hammer.zRotation))
                hammer.position = CGPoint(x: grip.x - rotatedGrip.x, y: grip.y - rotatedGrip.y)
            }
        }
        eyes.position.x += pose.gazeX * direction
        eyes.position.y += pose.gazeY
        openEyes.isHidden = false
        for eye in openEyes.children { eye.isHidden = false }
        tiredEyes.isHidden = true
        closedEyes.isHidden = true
        happyEyes.isHidden = true
        focusedEyes.isHidden = true
        surprisedEyes.isHidden = true
        brows.isHidden = true
        mouth.isHidden = false
        smileMouth.isHidden = true
        worriedMouth.isHidden = true
        surprisedMouth.isHidden = true
        displayedExpression = .focused
        if trick == .snatchRecall && hammerTrickTime < 0.65 {
            displayedExpression = .surprised
            openEyes.isHidden = true
            surprisedEyes.isHidden = false
            mouth.isHidden = true
            surprisedMouth.isHidden = false
        }
        if hammerTrickTime > trick.catchTime + 0.32 {
            displayedExpression = .proud
            openEyes.isHidden = true
            happyEyes.isHidden = false
            for lid in happyEyes.children { lid.isHidden = false }
            smileMouth.isHidden = false
            mouth.isHidden = true
        }
        coreGlow.alpha = max(coreGlow.alpha, pose.catchGlow)
        heldHammer.alpha = pose.opacity
        heldHammer.isHidden = pose.isAirborne
        flyingHammer.isHidden = !pose.isAirborne || onHammerFlight != nil
        if pose.isAirborne, let texture = heldHammer.texture {
            let grip = hammer.convert(heldHammer.position, to: stage)
            let reach = trick != .toss ? hammerRecallOffset.x / 140 : 1
            let lift = trick != .toss ? hammerRecallOffset.y / 65 : hammerTossHeightScale
            flyingHammer.position = CGPoint(x: grip.x + pose.offsetX * reach, y: grip.y + pose.offsetY * lift)
            flyingHammer.zRotation = pose.rotation * (reach < 0 ? -1 : 1) + hammer.zRotation
            flyingHammer.setScale(pose.scale)
            flyingHammer.alpha = pose.opacity
            let current = HammerFlightSample(position: flyingHammer.position,
                size: CGSize(width: heldHammer.size.width * pose.scale, height: heldHammer.size.height * pose.scale),
                rotation: flyingHammer.zRotation, opacity: pose.opacity)
            if flightHistory.last?.time != hammerTrickTime { flightHistory.append((hammerTrickTime, current)) }
            flightHistory.removeAll { hammerTrickTime - $0.time > 0.16 }
            var samples: [HammerFlightSample] = []
            for index in 0..<3 {
                guard pose.trailStrength > 0.03,
                      let past = flightHistory.last(where: { $0.time <= hammerTrickTime - Double(index + 1) * 0.032 }) else { continue }
                let sample = HammerFlightSample(position: past.sample.position, size: past.sample.size,
                    rotation: past.sample.rotation, opacity: pose.trailStrength * past.sample.opacity * (0.20 - Double(index) * 0.05))
                samples.append(sample)
                let ghost = hammerTrail.children[index] as! SKSpriteNode
                ghost.texture = texture
                ghost.position = sample.position
                ghost.size = sample.size
                ghost.zRotation = sample.rotation
                ghost.alpha = sample.opacity
                ghost.isHidden = onHammerFlight != nil
            }
            onHammerFlight?(HammerFlightFrame(texture: texture,
                position: stage.convert(flyingHammer.position, to: self),
                size: CGSize(width: current.size.width * characterScale, height: current.size.height * characterScale),
                rotation: flyingHammer.zRotation, opacity: pose.opacity, anchorPoint: flyingHammer.anchorPoint,
                trail: samples.map { sample in
                    HammerFlightSample(position: stage.convert(sample.position, to: self),
                        size: CGSize(width: sample.size.width * characterScale, height: sample.size.height * characterScale),
                        rotation: sample.rotation, opacity: sample.opacity)
                }))
        } else {
            flightHistory.removeAll()
            onHammerFlight?(nil)
        }
        if hammerTrickTime >= trick.catchTime && !trickCaught {
            trickCaught = true
            let grip = hammer.convert(heldHammer.position, to: stage)
            let impact = trick == .snatchRecall
            for _ in 0..<(impact ? 9 : 3) {
                let ember = flyingFlame(size: Double.random(in: impact ? 0.7...1.3 : 0.5...0.8))
                ember.position = grip
                addEmber(ember, vx: Double.random(in: impact ? -22...22 : -6...6),
                         vy: Double.random(in: impact ? 7...20 : 3...7),
                         life: Double.random(in: impact ? 0.2...0.4 : 0.15...0.25), gravity: 28)
            }
        }
    }

    private func cacheEmissionContour(_ node: SKSpriteNode, bands: Int = 1) {
        guard let texture = node.texture else { return }
        let bitmap = NSBitmapImageRep(cgImage: texture.cgImage())
        let columns = max(8, Int(node.size.width * 2))
        let rows = max(8, Int(node.size.height * 2))
        var points = Array(repeating: [CGPoint](), count: bands)
        for row in 0..<rows {
            let y = min(bitmap.pixelsHigh - 1, (row * 2 + 1) * bitmap.pixelsHigh / (rows * 2))
            var edges: [Int] = []
            for column in 0..<columns {
                let x = min(bitmap.pixelsWide - 1, (column * 2 + 1) * bitmap.pixelsWide / (columns * 2))
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.5 { edges.append(column) }
            }
            guard let first = edges.first, let last = edges.last else { continue }
            for column in [first, last] {
                // Bitmap rows start at the top; SpriteKit's local y grows upward.
                let point = CGPoint(x: ((CGFloat(column) + 0.5) / CGFloat(columns) - node.anchorPoint.x) * node.size.width,
                                    y: (1 - (CGFloat(row) + 0.5) / CGFloat(rows) - node.anchorPoint.y) * node.size.height)
                points[min(bands - 1, row * bands / rows)].append(point)
            }
        }
        for band in points where !band.isEmpty { emissionContours.append((node, band)) }
    }

    /// Three asymmetrical pixel silhouettes: a lick, a fleck and a split wisp.
    private func makeFlyingFlameTexture(variant: Int) -> SKTexture {
        let designs = [
            ["0001000", "0011000", "0012100", "0122100", "0123210",
             "1123210", "1233221", "1233321", "1233321", "0122210", "0011100"],
            ["0000000", "0000000", "0000100", "0001100", "0012100",
             "0123210", "1233210", "1232210", "0122100", "0011000", "0000000"],
            ["0100000", "0110010", "0120110", "0121210", "0122210",
             "0123210", "0123210", "0012210", "0012100", "0001100", "0001000"]
        ]
        let rows = designs[variant]
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
        let flame = SKSpriteNode(texture: effectTexture,
                                 size: CGSize(width: size, height: size * Double.random(in: 1.25...1.9)))
        flame.name = "flyingFlame"
        if motion.pose.charge > 0.08 {
            flame.shader = chargeShader
        } else if heat > 0.7 {
            flame.color = NSColor(red: 1, green: 0.9, blue: 0.6, alpha: 1)
            flame.colorBlendFactor = 0.15
        }
        let tail = SKSpriteNode(texture: flame.texture,
                               size: CGSize(width: size * 0.45, height: size * Double.random(in: 0.7...1.4)))
        tail.alpha = 0.3
        tail.color = NSColor(red: 0.94, green: 0.32, blue: 0.06, alpha: 1)
        tail.colorBlendFactor = 0.6
        tail.shader = flame.shader
        tail.name = "flameTail"
        tail.anchorPoint = CGPoint(x: 0.5, y: 1)
        tail.position.y = -size * 0.25
        tail.zPosition = -1
        flame.addChild(tail)
        return flame
    }

    private func addEmber(_ node: SKSpriteNode, vx: Double, vy: Double, life: Double, gravity: Double) {
        guard particles.count < 80 else { return }
        sparks.addChild(node)
        particles.append(Ember(node: node, vx: vx, vy: vy, life: life, gravity: gravity,
                               drag: Double.random(in: 0.5...1.6), curl: Double.random(in: 1.4...4.8),
                               phase: Double.random(in: 0...(.pi * 2)), flutter: Double.random(in: 7...15)))
    }

    private func emitSparks(strength: Double) {
        let contact = CGPoint(x: -22.7, y: 0)
        for _ in 0..<(strength > 0.8 ? 8 : 4) {
            let pixel = flyingFlame(size: Double.random(in: 0.55...1.6))
            pixel.position = CGPoint(x: contact.x + Double.random(in: -0.6...0.6),
                                     y: contact.y + Double.random(in: -0.4...0.4))
            addEmber(pixel, vx: Double.random(in: -22...22), vy: Double.random(in: 12...27),
                     life: Double.random(in: 0.28...0.72), gravity: Double.random(in: 38...60))
        }
    }

    private func emitEmbers(count: Int, celebration: Bool, heat: Double) {
        guard !emissionContours.isEmpty else { return }
        for _ in 0..<min(count, max(0, 80 - particles.count)) {
            // Mostly tiny flecks, with occasional larger torn-off licks.
            let sizeBias = Double.random(in: 0...1)
            let side = 0.65 + 2.35 * sizeBias * sizeBias
            let pixel = flyingFlame(size: side, heat: heat)
            if emissionOrder.isEmpty { emissionOrder = emissionContours.indices.shuffled() }
            let contour = emissionContours[emissionOrder.removeLast()]
            let point = contour.points.randomElement()!
            pixel.position = contour.node.convert(point, to: stage)
            pixel.position.x += Double.random(in: -0.3...0.3)
            pixel.position.y += Double.random(in: -0.3...0.3)
            let outward = (pixel.position.x / 18) * Double.random(in: 1.5...5.5)
            let angle = Double.random(in: 0...(.pi * 2))
            addEmber(pixel, vx: celebration ? cos(angle) * Double.random(in: 10...24) : outward + Double.random(in: -2...2),
                     vy: celebration ? sin(angle) * 15 + 10 : Double.random(in: 5...13),
                     life: Double.random(in: 0.6...1.65), gravity: celebration ? 6 : Double.random(in: -4 ... -1))
        }
    }

    private func updateSparks(by delta: Double) {
        for index in particles.indices {
            particles[index].age += delta
            var p = particles[index]
            let wind = 1.6 * sin(flameTime * 0.8) + 0.7 * sin(flameTime * 1.7)
            let curl = sin(p.phase + p.age * 3.4) * p.curl
            p.vx += (wind + curl - p.drag * p.vx) * delta
            p.vy -= (p.gravity + p.drag * 0.2 * p.vy) * delta
            p.node.position.x += p.vx * delta
            p.node.position.y += p.vy * delta
            let progress = p.age / p.life
            // Staggered cooling and flutter, with a short birth fade instead of popping in.
            p.node.alpha = min(1, p.age / 0.065) * pow(max(0, 1 - progress), 0.65)
            let flutter = sin(p.phase + p.age * p.flutter)
            p.node.xScale = max(0.12, 1 - 0.8 * progress) * (1 + 0.08 * flutter)
            p.node.yScale = max(0.15, 1 - 0.7 * progress) * (1 - 0.12 * flutter)
            p.node.zRotation = atan2(-p.vx, max(2, p.vy)) * 0.6 + flutter * 0.10
            if p.node.shader == nil {
                p.node.color = NSColor(red: 0.88, green: 0.26, blue: 0.055, alpha: 1)
                p.node.colorBlendFactor = progress * 0.65
            }
            if let tail = p.node.childNode(withName: "flameTail") {
                tail.yScale = (0.6 + 0.25 * flutter) * (1 - progress)
                tail.alpha = 0.3 * (1 - progress)
            }
            particles[index] = p
        }
        particles.removeAll { particle in
            if particle.age >= particle.life { particle.node.removeFromParent(); return true }
            return false
        }
    }
}
