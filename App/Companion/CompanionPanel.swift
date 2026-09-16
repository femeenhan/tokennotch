import AppKit
import SpriteKit
import SpiritCore

@MainActor
final class CompanionPanel: NSPanel {
    let spiritView: CompanionView
    let spiritScene: SpiritScene
    private(set) lazy var interactionPanel = InteractionPanel()
    var positionChanged: ((CGPoint) -> Void)?
    var clicked: (() -> Void)?
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
        interactionPanel.interactionView.companion = self
        syncInteractionFrame()
    }

    func resize(to size: Double) {
        setContentSize(CGSize(width: size, height: size))
        syncInteractionFrame()
    }

    private func syncInteractionFrame() {
        interactionPanel.setFrame(CompanionGeometry.interactionFrame(
            visualOrigin: frame.origin, size: frame.width), display: true)
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

    func setRendering(active: Bool) {
        spiritView.isPaused = !active
        if active {
            syncInteractionFrame()
            orderFrontRegardless()
            interactionPanel.orderFrontRegardless()
        } else {
            interactionPanel.interactionView.cancelDrag()
            interactionPanel.orderOut(nil)
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
        interactionView.setAccessibilityLabel("빌드정령 캐릭터. 드래그로 이동, 클릭으로 요약 확인, 우클릭으로 메뉴 열기")
        contentView = interactionView
    }
}

@MainActor
final class InteractionView: NSView {
    weak var companion: CompanionPanel?
    private var dragStart: CGPoint?
    private var windowStart: CGPoint = .zero
    private var didDrag = false
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = companion?.frame.origin ?? .zero
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        if hypot(mouse.x - start.x, mouse.y - start.y) > 3 { didDrag = true }
        companion?.move(to: CGPoint(x: windowStart.x + mouse.x - start.x,
                                   y: windowStart.y + mouse.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil, let panel = companion else { return }
        let dragged = didDrag
        dragStart = nil
        if dragged { panel.correctPosition() }
        if !dragged { panel.clicked?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        companion?.contextMenuRequested?()
    }

    func cancelDrag() {
        dragStart = nil
        didDrag = false
    }
}
