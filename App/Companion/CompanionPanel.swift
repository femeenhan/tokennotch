import AppKit
import SpriteKit
import SpiritCore

@MainActor
final class CompanionPanel: NSPanel {
    let spiritView: CompanionView
    let spiritScene: SpiritScene
    private(set) lazy var interactionPanel = InteractionPanel()
    private(set) lazy var speechPanel = SpeechPanel()
    private(set) lazy var flameTrailPanel = FlameTrailPanel()
    private var speechState: SpiritState?
    private var renderingActive = false
    var positionChanged: ((CGPoint) -> Void)?
    var clicked: (() -> Void)?
    var transformed: (() -> Void)?
    var contextMenuRequested: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(size: Double) {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        spiritView = CompanionView(frame: rect)
        spiritScene = SpiritScene(size: rect.size)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        // The entire visual surface passes clicks through, independent of rendered alpha.
        ignoresMouseEvents = true
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        setAccessibilityElement(false)
        spiritView.allowsTransparency = true
        spiritView.preferredFramesPerSecond = 60
        spiritView.presentScene(spiritScene)
        spiritView.setAccessibilityElement(false)
        contentView = spiritView
        speechPanel.speechView.dismiss = { [weak self] in self?.dismissSpeech() }
        interactionPanel.interactionView.companion = self
        spiritScene.onTransform = { [weak self] in
            guard let self else { return }
            self.transformed?()
            self.speechPanel.speechView.message = "으아아! 불꽃 충전!"
            self.positionSpeech()
            if self.renderingActive { self.speechPanel.orderFrontRegardless() }
        }
        syncInteractionFrame()
    }

    func resize(to size: Double) {
        setContentSize(CGSize(width: size, height: size))
        syncInteractionFrame()
    }

    private func syncInteractionFrame() {
        interactionPanel.setFrame(CompanionGeometry.interactionFrame(
            visualOrigin: frame.origin, size: frame.width), display: true)
        positionSpeech()
    }

    func move(to point: CGPoint) {
        setFrameOrigin(point)
        syncInteractionFrame()
    }

    func correctPosition(_ origin: CGPoint? = nil) {
        guard let primary = NSScreen.screens.first else { return }
        let point = CompanionGeometry.safeOrigin(origin ?? frame.origin, size: frame.width,
            visibleFrames: NSScreen.screens.map(\.visibleFrame), primaryFrame: primary.visibleFrame)
        move(to: point)
        positionChanged?(point)
    }

    func updateSpeech(state: SpiritState) {
        guard speechState != state else { return }
        let previousState = speechState
        speechState = state
        // Brief greetings/completion poses finish quickly; keep their words until tapped.
        if state == .idle && previousState != .working && previousState != .attention && previousState != .error {
            return
        }
        let message = state == .idle ? "언제든 불러 줘!" : SpeechPanel.message(for: state)
        speechPanel.speechView.message = message
        positionSpeech()
        if message != nil && renderingActive { speechPanel.orderFrontRegardless() }
        else { speechPanel.orderOut(nil) }
    }

    @discardableResult
    func dismissSpeech() -> Bool {
        guard speechPanel.speechView.message != nil else { return false }
        speechPanel.speechView.message = nil
        speechPanel.orderOut(nil)
        return true
    }

    private func positionSpeech() {
        let placement = UsageBubblePlacement.place(characterFrame: frame,
            visibleFrames: NSScreen.screens.map(\.visibleFrame), size: SpeechPanel.size)
        speechPanel.setFrame(placement.frame, display: true)
        speechPanel.speechView.tailOnLeft = placement.tailOnLeft
        speechPanel.speechView.tailY = placement.tailYFromTop
        speechPanel.speechView.needsDisplay = true
    }

    func setRendering(active: Bool) {
        renderingActive = active
        spiritView.isPaused = !active
        if active {
            syncInteractionFrame()
            orderFrontRegardless()
            interactionPanel.orderFrontRegardless()
            if speechPanel.speechView.message != nil { speechPanel.orderFrontRegardless() }
        } else {
            interactionPanel.interactionView.cancelDrag()
            flameTrailPanel.clear()
            interactionPanel.orderOut(nil)
            speechPanel.orderOut(nil)
            orderOut(nil)
        }
    }
}

@MainActor
final class CompanionView: SKView {
    override var isOpaque: Bool { false }
}

@MainActor
final class InteractionPanel: NSPanel {
    let interactionView = InteractionView(frame: .zero)
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "빌드정령 캐릭터 입력"
        // A faint fill makes the deliberate rig-sized input target reliable for WindowServer.
        // This includes small transparent gaps between parts; outer window corners pass through.
        backgroundColor = NSColor.black.withAlphaComponent(0.01)
        isOpaque = false
        ignoresMouseEvents = false
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        interactionView.setAccessibilityElement(true)
        interactionView.setAccessibilityRole(.button)
        interactionView.setAccessibilityLabel("빌드정령 캐릭터. 드래그로 이동, 반복 클릭 또는 길게 눌러 불꽃 충전, 클릭으로 요약 확인, 우클릭으로 메뉴 열기")
        contentView = interactionView
    }
}

@MainActor
final class InteractionView: NSView {
    weak var companion: CompanionPanel?
    private var dragStart: CGPoint?
    private var windowStart: CGPoint = .zero
    private var didDrag = false
    private var previousDragPoint: CGPoint?
    private var previousDragTime: TimeInterval = 0
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = companion?.frame.origin ?? .zero
        didDrag = false
        previousDragPoint = dragStart
        previousDragTime = event.timestamp
        companion?.spiritScene.beginPress()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        if !didDrag && hypot(mouse.x - start.x, mouse.y - start.y) > 3 {
            didDrag = true
            _ = companion?.spiritScene.endPress(registerTap: false)
        }
        guard didDrag, let panel = companion else { return }
        let elapsed = max(1.0 / 120, min(0.1, event.timestamp - previousDragTime))
        let previous = previousDragPoint ?? mouse
        let velocity = CGPoint(x: max(-1800, min(1800, (mouse.x - previous.x) / elapsed)),
                               y: max(-1800, min(1800, (mouse.y - previous.y) / elapsed)))
        let oldCenter = CGPoint(x: panel.frame.midX, y: panel.frame.minY + panel.frame.height * 0.46)
        panel.move(to: CGPoint(x: windowStart.x + mouse.x - start.x,
                              y: windowStart.y + mouse.y - start.y))
        panel.spiritScene.setDragVelocity(x: Double(velocity.x), y: Double(velocity.y))
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.minY + panel.frame.height * 0.46)
        panel.flameTrailPanel.emit(from: oldCenter, to: center, velocity: velocity,
                                  texture: panel.spiritScene.effectTexture, companion: panel)
        previousDragPoint = mouse
        previousDragTime = event.timestamp
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil, let panel = companion else { return }
        let dragged = didDrag
        dragStart = nil
        previousDragPoint = nil
        panel.spiritScene.setDragVelocity(x: 0, y: 0)
        let charged = panel.spiritScene.endPress(registerTap: !dragged)
        if dragged { panel.correctPosition() }
        if !dragged && !charged && !panel.dismissSpeech() { panel.clicked?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        companion?.contextMenuRequested?()
    }

    func cancelDrag() {
        dragStart = nil
        didDrag = false
        previousDragPoint = nil
        companion?.spiritScene.setDragVelocity(x: 0, y: 0)
        _ = companion?.spiritScene.endPress(registerTap: false)
    }
}


/// A small nonactivating speech window keeps dialogue readable outside the sprite bounds.
@MainActor
final class SpeechPanel: NSPanel {
    static let size = CGSize(width: 188, height: 70)
    static func message(for state: SpiritState) -> String? {
        switch state {
        case .idle: return nil
        case .working: return "열심히 만드는 중…"
        case .attention: return "잠깐! 나 좀 봐줘"
        case .completed: return "다 만들었어!"
        case .greeting: return "안녕! 같이 만들자"
        case .error: return "앗, 연결을 확인해 줘"
        case .sleeping: return "잠깐 쉬고 올게…"
        }
    }
    let speechView = SpiritSpeechView(frame: CGRect(origin: .zero, size: SpeechPanel.size))
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: CGRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "빌드정령 말풍선"
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        contentView = speechView
    }
}

@MainActor
final class SpiritSpeechView: NSView {
    var message: String? {
        didSet {
            needsDisplay = true
            setAccessibilityLabel(message.map { "\($0). 눌러서 말풍선 닫기" })
        }
    }
    var tailOnLeft = true
    var tailY: Double = 35
    var dismiss: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityPerformPress() -> Bool { dismiss?(); return true }
    override func mouseUp(with event: NSEvent) { dismiss?() }

    override func draw(_ dirtyRect: NSRect) {
        guard let message else { return }
        let width = bounds.width
        let height = bounds.height
        let tail = min(max(CGFloat(tailY), 17), height - 17)
        // Pixel steps keep the bubble and its little tail in the sprite's visual language.
        var points: [CGPoint] = [
            CGPoint(x: 18, y: 2), CGPoint(x: width - 18, y: 2),
            CGPoint(x: width - 18, y: 6), CGPoint(x: width - 14, y: 6),
            CGPoint(x: width - 14, y: 10), CGPoint(x: width - 10, y: 10),
            CGPoint(x: width - 10, y: height - 10), CGPoint(x: width - 14, y: height - 10),
            CGPoint(x: width - 14, y: height - 6), CGPoint(x: width - 18, y: height - 6),
            CGPoint(x: width - 18, y: height - 2), CGPoint(x: 18, y: height - 2),
            CGPoint(x: 18, y: height - 6), CGPoint(x: 14, y: height - 6),
            CGPoint(x: 14, y: height - 10), CGPoint(x: 10, y: height - 10),
            CGPoint(x: 10, y: tail + 8), CGPoint(x: 6, y: tail + 8),
            CGPoint(x: 6, y: tail + 4), CGPoint(x: 2, y: tail + 4),
            CGPoint(x: 2, y: tail), CGPoint(x: 6, y: tail),
            CGPoint(x: 6, y: tail - 4), CGPoint(x: 10, y: tail - 4),
            CGPoint(x: 10, y: 10), CGPoint(x: 14, y: 10),
            CGPoint(x: 14, y: 6), CGPoint(x: 18, y: 6)
        ]
        if !tailOnLeft { points = points.map { CGPoint(x: width - $0.x, y: $0.y) } }
        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() { path.line(to: point) }
        path.close()
        NSColor(calibratedRed: 1, green: 0.95, blue: 0.82, alpha: 1).setFill()
        path.fill()
        NSColor(calibratedRed: 0.37, green: 0.23, blue: 0.14, alpha: 1).setStroke()
        path.lineWidth = 2
        path.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let font = NSFont(name: "NeoDunggeunmo-Regular", size: 15)
            ?? .systemFont(ofSize: 14, weight: .semibold)
        let textColor = NSColor(calibratedRed: 0.29, green: 0.18, blue: 0.11, alpha: 1)
        (message as NSString).draw(in: CGRect(x: 15, y: 18, width: width - 30, height: 23),
            withAttributes: [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph])
        ("톡 눌러 닫기" as NSString).draw(in: CGRect(x: 15, y: 43, width: width - 30, height: 15),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10),
                             .foregroundColor: textColor.withAlphaComponent(0.65),
                             .paragraphStyle: paragraph])
    }
}


/// Screen-space embers retain their position while the companion window moves.
@MainActor
final class FlameTrailPanel: NSPanel {
    private let trailView = CompanionView(frame: CGRect(x: 0, y: 0, width: 384, height: 384))
    private let trailScene = FlameTrailScene(size: CGSize(width: 384, height: 384))
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: trailView.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = true
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        trailView.allowsTransparency = true
        trailView.preferredFramesPerSecond = 30
        trailView.isPaused = true
        trailView.presentScene(trailScene)
        contentView = trailView
        trailScene.finished = { [weak self] in self?.clear() }
    }

    func emit(from start: CGPoint, to end: CGPoint, velocity: CGPoint,
              texture: SKTexture, companion: CompanionPanel) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            clear()
            return
        }
        let origin = CGPoint(x: end.x - 192, y: end.y - 192)
        let shift = CGPoint(x: frame.minX - origin.x, y: frame.minY - origin.y)
        for ember in trailScene.children {
            ember.position.x += shift.x
            ember.position.y += shift.y
        }
        setFrameOrigin(origin)
        let speed = hypot(velocity.x, velocity.y)
        guard speed > 20 else { return }
        let count = min(8, max(2, Int(hypot(end.x - start.x, end.y - start.y) / 10)))
        for index in 0..<count {
            let progress = CGFloat(index + 1) / CGFloat(count)
            let position = CGPoint(x: start.x + (end.x - start.x) * progress - origin.x,
                                   y: start.y + (end.y - start.y) * progress - origin.y)
            let ember = SKSpriteNode(texture: texture)
            let side = CGFloat.random(in: 7...13)
            ember.size = CGSize(width: side, height: side * 1.6)
            ember.position = CGPoint(x: position.x + CGFloat.random(in: -10...10),
                                     y: position.y + CGFloat.random(in: -8...8))
            ember.color = index.isMultiple(of: 2) ? .systemOrange : .systemYellow
            ember.shader = companion.spiritScene.effectShader
            ember.colorBlendFactor = ember.shader == nil ? 0.35 : 0
            ember.zRotation = atan2(velocity.y, velocity.x) + .pi / 2
            trailScene.addChild(ember)
            let drift = SKAction.moveBy(x: -velocity.x * 0.035, y: -velocity.y * 0.035 + 18, duration: 0.48)
            drift.timingMode = .easeOut
            ember.run(.sequence([.group([drift, .fadeOut(withDuration: 0.48),
                                         .scale(to: 0.35, duration: 0.48)]), .removeFromParent()]))
        }
        // Keep the bounded trail inexpensive, even during a very rapid drag.
        while trailScene.children.count > 96 { trailScene.children.first?.removeFromParent() }
        trailView.isPaused = false
        order(.below, relativeTo: companion.windowNumber)
    }

    func clear() {
        trailScene.removeAllChildren()
        trailView.isPaused = true
        orderOut(nil)
    }
}

@MainActor
private final class FlameTrailScene: SKScene {
    var finished: (() -> Void)?
    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didEvaluateActions() {
        if children.isEmpty { finished?() }
    }
}
