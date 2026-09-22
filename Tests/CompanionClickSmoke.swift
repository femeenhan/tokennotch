import AppKit
import SpriteKit
import SpiritCore

/// Native event routing regression: right-click must not trigger the left-click action.
@main
@MainActor
struct CompanionClickSmoke {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let panel = CompanionPanel(size: 192)
        let input = panel.interactionPanel.interactionView
        var leftClicks = 0
        var contextMenus = 0
        panel.clicked = { leftClicks += 1 }
        panel.contextMenuRequested = { contextMenus += 1 }

        func require(_ condition: Bool, _ message: String) {
            guard condition else {
                print("FAIL: \(message)")
                exit(1)
            }
        }
        let label = panel.spiritScene.childNode(withName: "//providerLabel")!
        panel.spiritScene.setProviderLabelVisible(false)
        require(label.isHidden, "Provider name must be hidden at rest")
        panel.spiritScene.update(0)
        panel.spiritScene.setProviderLabelVisible(true)
        let mask = (panel.spiritScene.childNode(withName: "providerNameplate") as! SKCropNode).maskNode!
        require(!label.isHidden && mask.xScale == 0, "Hover must start a reveal, not pop in")
        panel.spiritScene.update(0.06)
        require(mask.xScale > 0 && mask.xScale < 1, "Nameplate must be partially unfolded mid-animation")
        let partialReveal = mask.xScale
        panel.spiritScene.render(state: .working, reduceMotion: false)
        require(mask.xScale == partialReveal, "State updates must preserve reveal progress")
        panel.spiritScene.setProviderLabelVisible(false)
        require(mask.xScale == partialReveal, "Rapid hover exit must not jump")
        panel.spiritScene.update(0.12)
        require(label.isHidden && mask.xScale == 0, "Nameplate must fold away after hover exit")
        panel.spiritScene.setProviderLabelVisible(true)
        for step in 3...6 { panel.spiritScene.update(Double(step) * 0.06) }
        require(mask.xScale == 1, "Nameplate must fully unfold")
        panel.spiritScene.render(state: .idle, reduceMotion: true)
        panel.spiritScene.setProviderLabelVisible(false)
        require(label.isHidden && mask.xScale == 0, "Reduced motion must hide without animation")
        panel.spiritScene.render(state: .idle, reduceMotion: false)
        require(SpeechPanel.size.height == 44, "Dialogue must use compact single-line height")
        var interactionTime = 1.0
        panel.spiritScene.update(interactionTime)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            if type == .leftMouseDown {
                for _ in 0..<60 {
                    interactionTime += 1.0 / 60
                    panel.spiritScene.update(interactionTime)
                }
            }
            let body = panel.spiritScene.childNode(withName: "//body")!
            let bodyPoint = body.convert(CGPoint(x: 3, y: 8), to: panel.spiritScene)
            let viewPoint = panel.spiritScene.convertPoint(toView: bodyPoint)
            let screenPoint = panel.convertPoint(toScreen: panel.spiritView.convert(viewPoint, to: nil))
            let inputPoint = panel.interactionPanel.convertPoint(fromScreen: screenPoint)
            guard let event = NSEvent.mouseEvent(with: type,
                location: inputPoint,
                modifierFlags: [], timestamp: 0,
                windowNumber: panel.interactionPanel.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1) else {
                fatalError("Could not construct native mouse event")
            }
            return event
        }

        input.mouseDown(with: event(.leftMouseDown))
        input.mouseUp(with: event(.leftMouseUp))
        require(leftClicks == 1, "A stationary left-click must invoke the usage-panel action once")
        require(contextMenus == 0, "Left-click must not open the context menu")
        input.rightMouseDown(with: event(.rightMouseDown))
        require(leftClicks == 1, "Right-click incorrectly invokes the left-click usage-panel action")
        require(contextMenus == 1, "Right-click must invoke the context menu exactly once")
        input.mouseUp(with: event(.leftMouseUp))
        require(leftClicks == 1, "An unmatched mouse-up must not invoke a click")
        input.mouseDown(with: event(.leftMouseDown))
        input.mouseUp(with: event(.leftMouseUp))
        require(leftClicks == 2 && contextMenus == 1,
                "Left-click must continue working independently after a context-menu click")
        input.mouseDown(with: event(.leftMouseDown))
        input.cancelDrag()
        input.mouseUp(with: event(.leftMouseUp))
        require(leftClicks == 2 && contextMenus == 1,
                "Canceling an interaction must suppress its later mouse-up click")
        panel.updateSpeech(state: .idle)
        panel.setRendering(active: true)
        require(!panel.speechPanel.isVisible, "Initial idle must not display dialogue")
        panel.updateSpeech(state: .working)
        require(panel.speechPanel.isVisible, "Working dialogue must be visible with the companion")
        let workingMessage = panel.speechPanel.speechView.message
        input.mouseDown(with: event(.leftMouseDown))
        input.mouseUp(with: event(.leftMouseUp))
        require(leftClicks == 2 && !panel.speechPanel.isVisible,
                "Character click must dismiss its dialogue before opening usage")
        panel.updateSpeech(state: .working)
        require(panel.speechPanel.speechView.message == nil && !panel.speechPanel.isVisible,
                "Polling the same state must not restore dismissed dialogue")
        input.mouseDown(with: event(.leftMouseDown))
        input.mouseUp(with: event(.leftMouseUp))
        require(leftClicks == 3, "A subsequent character click must open usage")
        panel.updateSpeech(state: .attention)
        require(panel.speechPanel.speechView.message != workingMessage && panel.speechPanel.isVisible,
                "A state change must display new dialogue")
        let speechOrigin = panel.speechPanel.frame.origin
        panel.move(to: CGPoint(x: panel.frame.minX + 12, y: panel.frame.minY + 12))
        require(panel.speechPanel.frame.origin != speechOrigin, "Dialogue must follow companion movement")
        panel.setRendering(active: false)
        require(!panel.speechPanel.isVisible, "Hidden companions must hide their dialogue")
        panel.setRendering(active: true)
        require(panel.speechPanel.isVisible, "Showing companions must restore undismissed dialogue")
        let speechView = panel.speechPanel.speechView
        if let bitmap = speechView.bitmapImageRepForCachingDisplay(in: speechView.bounds) {
            speechView.cacheDisplay(in: speechView.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                let capture = URL(fileURLWithPath: "/tmp/build-spirit-speech-bubble.png")
                try? png.write(to: capture)
                print("Speech bubble capture: \(capture.path)")
            }
        }
        let originalMessage = speechView.message
        for (index, message) in ["열심히 만드는 중…", "잠깐! 나 좀 봐줘", "다 만들었어!", "안녕! 같이 만들자", "앗, 연결을 확인해 줘", "잠깐 쉬고 올게…", "언제든 불러 줘!", "으아아! 불꽃 충전!"].enumerated() {
            speechView.message = message
            let bitmap = speechView.bitmapImageRepForCachingDisplay(in: speechView.bounds)!
            speechView.cacheDisplay(in: speechView.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/spirit-speech-\(index).png"))
            var ink = 0
            for y in Int(10 * bitmap.pixelsHigh / 44)..<Int(34 * bitmap.pixelsHigh / 44) {
                for x in Int(18 * bitmap.pixelsWide / 188)..<Int(170 * bitmap.pixelsWide / 188) {
                    let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    if color.redComponent < 0.6 && color.alphaComponent > 0.5 { ink += 1 }
                }
            }
            require(ink > 50, "Dialogue must paint visible glyphs: \(message)")
        }
        speechView.message = originalMessage
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let speechClick = NSEvent.mouseEvent(with: type,
                location: CGPoint(x: speechView.bounds.midX, y: speechView.bounds.midY),
                modifierFlags: [], timestamp: 0,
                windowNumber: panel.speechPanel.windowNumber, context: nil,
                eventNumber: 2, clickCount: 1, pressure: 1) else {
                fatalError("Could not construct native speech mouse event")
            }
            panel.speechPanel.sendEvent(speechClick)
        }
        require(!panel.speechPanel.isVisible && leftClicks == 3,
                "Native speech-window click must dismiss without opening usage")
        panel.updateSpeech(state: .completed)
        require(panel.speechPanel.isVisible, "Completion must show fresh dialogue")
        panel.updateSpeech(state: .idle)
        require(!panel.speechPanel.isVisible && panel.speechPanel.speechView.message == nil,
                "Completion dialogue must close when its brief pose ends")
        panel.dismissSpeech()
        panel.updateSpeech(state: .idle)
        require(!panel.speechPanel.isVisible, "Dismissed completion must stay hidden while idle")
        panel.setRendering(active: true)
        let clicksBeforeHold = leftClicks
        input.mouseDown(with: event(.leftMouseDown))
        for _ in 0..<100 {
            interactionTime += 1.0 / 60
            panel.spiritScene.update(interactionTime)
        }
        input.mouseUp(with: event(.leftMouseUp))
        require(leftClicks == clicksBeforeHold, "Charged release must not open usage")
        require(panel.speechPanel.speechView.message == "으아아! 불꽃 충전!",
                "Charged release must retain transformation dialogue until a later tap")
        for _ in 0..<900 {
            interactionTime += 1.0 / 60
            panel.spiritScene.update(interactionTime)
        }
        require(panel.speechPanel.speechView.message == nil && !panel.speechPanel.isVisible,
                "Charge dialogue must close automatically when charge ends")
        panel.updateSpeech(state: .error)
        RunLoop.current.run(until: Date().addingTimeInterval(3.15))
        require(!panel.speechPanel.isVisible, "Long-running state dialogue must expire without clicking")
        panel.updateSpeech(state: .error)
        require(!panel.speechPanel.isVisible, "Polling must not restore expired dialogue")
        require(panel.flameTrailPanel.ignoresMouseEvents && !panel.flameTrailPanel.canBecomeKey,
                "Decorative drag flames must neither capture clicks nor activate")
        require(panel.hammerFlightPanel.ignoresMouseEvents && !panel.hammerFlightPanel.canBecomeKey,
                "A flying hammer must neither capture desktop clicks nor activate")
        let flightPosition = CGPoint(x: panel.spiritScene.size.width + 220,
                                     y: panel.spiritScene.size.height * 0.7)
        let flight = HammerFlightFrame(texture: panel.spiritScene.effectTexture,
            position: flightPosition, size: CGSize(width: 64, height: 38),
            rotation: 0.73, opacity: 0.8, anchorPoint: CGPoint(x: 0.92, y: 0.15),
            trail: [
                HammerFlightSample(position: CGPoint(x: flightPosition.x + 72, y: flightPosition.y + 24),
                                   size: CGSize(width: 64, height: 38), rotation: -1.2, opacity: 0.18),
                HammerFlightSample(position: CGPoint(x: flightPosition.x + 144, y: flightPosition.y + 40),
                                   size: CGSize(width: 64, height: 38), rotation: 2.1, opacity: 0.10)
            ])
        panel.spiritScene.onHammerFlight?(flight)
        require(panel.hammerFlightPanel.isVisible,
                "A flying hammer outside the character window must remain visible")
        if let hammerView = panel.hammerFlightPanel.contentView as? SKView,
           let hammerScene = hammerView.scene, let hammer = hammerScene.children.first {
            let sourcePoint = panel.spiritView.convert(
                panel.spiritScene.convertPoint(toView: flightPosition), to: nil)
            let expected = panel.convertPoint(toScreen: sourcePoint)
            let actual = CGPoint(x: panel.hammerFlightPanel.frame.minX + hammer.position.x,
                                 y: panel.hammerFlightPanel.frame.minY + hammer.position.y)
            require(hypot(expected.x - actual.x, expected.y - actual.y) < 0.01,
                    "The external hammer grip must preserve exact screen coordinates")
            require(CGRect(origin: .zero, size: hammerScene.size).contains(hammer.calculateAccumulatedFrame()),
                    "A rotated hammer with an offset grip must fit inside its external window")
            let ghosts = hammerScene.children.filter { $0.name?.hasPrefix("hammerTrail") == true }
            require(ghosts.count == 2, "The desktop overlay must preserve scene-provided trail samples")
            for (index, ghost) in ghosts.enumerated() {
                require(CGRect(origin: .zero, size: hammerScene.size).contains(ghost.calculateAccumulatedFrame()),
                        "Every rotated trail sample must fit inside the desktop overlay")
                require(ghost.alpha <= 0.20 && ghost.zPosition < hammer.zPosition,
                        "Hammer afterimages must remain faint and behind the real tool")
                let source = panel.spiritView.convert(
                    panel.spiritScene.convertPoint(toView: flight.trail[index].position), to: nil)
                let target = panel.convertPoint(toScreen: source)
                let displayed = CGPoint(x: panel.hammerFlightPanel.frame.minX + ghost.position.x,
                                        y: panel.hammerFlightPanel.frame.minY + ghost.position.y)
                require(hypot(target.x - displayed.x, target.y - displayed.y) < 0.01,
                        "Trail samples must preserve their exact scene-to-screen position")
            }
            require(!panel.frame.contains(expected),
                    "The regression must exercise a hammer beyond the original sprite window")
        } else {
            require(false, "The flying hammer requires its own sprite scene")
        }
        panel.spiritScene.onHammerFlight?(nil)
        require(!panel.hammerFlightPanel.isVisible,
                "Catching the hammer must remove its external surface immediately")
        if let view = panel.hammerFlightPanel.contentView as? SKView {
            require(view.scene?.children.contains(where: { $0.name?.hasPrefix("hammerTrail") == true }) == false,
                    "Catching or cancelling must remove every afterimage immediately")
        }
        panel.spiritScene.onHammerFlight?(flight)
        panel.setRendering(active: false)
        require(!panel.hammerFlightPanel.isVisible,
                "Hiding the companion must clear an in-flight hammer")
        panel.setRendering(active: true)
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           let trailView = panel.flameTrailPanel.contentView as? SKView,
           let trailScene = trailView.scene {
            // Many tiny mouse events must not each produce a minimum particle count.
            for sample in 0..<100 {
                panel.flameTrailPanel.emit(
                    from: CGPoint(x: center.x + Double(sample) * 0.1, y: center.y),
                    to: CGPoint(x: center.x + Double(sample + 1) * 0.1, y: center.y),
                    velocity: CGPoint(x: 100, y: 0),
                    texture: panel.spiritScene.effectTexture, companion: panel)
                trailView.isPaused = true
            }
            require((1...3).contains(trailScene.children.count),
                    "A 10pt movement must emit by traveled distance, not by its 100 input events")
            let stationaryCount = trailScene.children.count
            panel.flameTrailPanel.emit(from: center, to: center, velocity: CGPoint(x: 1000, y: 0),
                                      texture: panel.spiritScene.effectTexture, companion: panel)
            require(trailScene.children.count == stationaryCount,
                    "A stale velocity without movement must not emit drag flames")
            panel.flameTrailPanel.clear()
            for sample in 0..<40 {
                panel.flameTrailPanel.emit(
                    from: CGPoint(x: center.x + Double(sample) * 12, y: center.y),
                    to: CGPoint(x: center.x + Double(sample + 1) * 12, y: center.y),
                    velocity: CGPoint(x: 800, y: 0),
                    texture: panel.spiritScene.effectTexture, companion: panel)
                trailView.isPaused = true
            }
            let sprites = trailScene.children.compactMap { $0 as? SKSpriteNode }
            let widths = sprites.map { $0.size.width }
            let heights = sprites.map { $0.position.y }
            require(sprites.count > 20 && sprites.count <= 96,
                    "A continuous drag must leave a bounded, distance-spaced trail")
            require((widths.max() ?? 0) > (widths.min() ?? 0) * 2,
                    "Trail flames must mix small embers and larger fragments")
            require((heights.max() ?? 0) - (heights.min() ?? 0) > 18,
                    "Horizontal dragging must shed embers across the rear edge, not a center line")
            panel.flameTrailPanel.emit(from: center, to: CGPoint(x: center.x + 3000, y: center.y),
                                      velocity: CGPoint(x: 1800, y: 0),
                                      texture: panel.spiritScene.effectTexture, companion: panel)
            require(trailScene.children.count <= 96, "A large drag jump must keep the particle cap")
            panel.flameTrailPanel.clear()
        }
        panel.flameTrailPanel.emit(from: center, to: CGPoint(x: center.x + 20, y: center.y),
                                  velocity: CGPoint(x: 300, y: 0),
                                  texture: panel.spiritScene.effectTexture, companion: panel)
        require(panel.flameTrailPanel.isVisible == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "Drag flames must respect the system Reduce Motion preference")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
           let trailView = panel.flameTrailPanel.contentView as? SKView,
           let trailScene = trailView.scene, let first = trailScene.children.first {
            trailView.isPaused = true
            let original = CGPoint(x: panel.flameTrailPanel.frame.minX + first.position.x,
                                   y: panel.flameTrailPanel.frame.minY + first.position.y)
            panel.flameTrailPanel.emit(from: center, to: CGPoint(x: center.x + 100, y: center.y + 20),
                velocity: CGPoint(x: 500, y: 100), texture: panel.spiritScene.effectTexture, companion: panel)
            trailView.isPaused = true
            let rebased = CGPoint(x: panel.flameTrailPanel.frame.minX + first.position.x,
                                  y: panel.flameTrailPanel.frame.minY + first.position.y)
            require(hypot(original.x - rebased.x, original.y - rebased.y) < 0.1,
                    "Existing flames must remain fixed in screen space when the trail window moves")
            guard let texture = trailView.texture(from: trailScene),
                  let png = NSBitmapImageRep(cgImage: texture.cgImage()).representation(using: .png, properties: [:])
            else { fatalError("Drag trail capture failed") }
            try! png.write(to: URL(fileURLWithPath: "/tmp/build-spirit-drag-trail.png"))
            trailView.isPaused = false
            RunLoop.current.run(until: Date().addingTimeInterval(1.15))
            require(trailScene.children.isEmpty && !panel.flameTrailPanel.isVisible,
                    "External flames must expire and hide their window automatically")
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.flameTrailPanel.emit(from: center, to: CGPoint(x: center.x + 50, y: center.y),
                velocity: CGPoint(x: 800, y: 0), texture: panel.spiritScene.effectTexture, companion: panel)
            let stalledView = panel.flameTrailPanel.contentView as! SKView
            stalledView.isPaused = true
            require(panel.flameTrailPanel.isVisible, "Stalled-renderer regression must start with visible embers")
            RunLoop.current.run(until: Date().addingTimeInterval(1.2))
            require(stalledView.scene!.children.isEmpty && !panel.flameTrailPanel.isVisible,
                    "Expired drag flames must clear even when SpriteKit stops advancing")
        }
        panel.setRendering(active: false)
        require(!panel.flameTrailPanel.isVisible, "Hiding companions must clear external drag flames")
        panel.setRendering(active: true)
        for side in [80.0, 128.0, 192.0] {
            panel.resize(to: side)
            panel.move(to: CGPoint(x: -300, y: 100))
            let frame = panel.interactionPanel.frame
            require(panel.frame.contains(frame), "Input window must stay inside visual window after resizing")
            for point in [CGPoint(x: 0.54, y: 0.23), CGPoint(x: 0.42, y: 0.83)] {
                let screen = CGPoint(x: panel.frame.minX + side * point.x, y: panel.frame.minY + side * point.y)
                require(frame.contains(screen), "Body and flame must receive clicks at every size")
            }
            // Particle sparks are decorative; test the animated character itself.
            panel.spiritScene.childNode(withName: "//sparks")?.isHidden = true
            var timestamp = 0.0
            for state in [SpiritState.idle, .working, .attention, .completed, .error, .greeting, .sleeping] {
                panel.spiritScene.render(state: state, reduceMotion: false)
                for sample in 0..<40 {
                    timestamp += 1.0 / 30
                    panel.spiritScene.update(timestamp)
                    if sample % 10 != 0 { continue }
                    require(panel.spiritScene.assetLoaded, "Native coverage verification requires the real rig asset")
                    guard let texture = panel.spiritView.texture(from: panel.spiritScene, crop: panel.spiritView.bounds) else {
                        fatalError("Could not render native character")
                    }
                    let bitmap = NSBitmapImageRep(cgImage: texture.cgImage())
                    var visibleSamples = 0
                    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
                        let localY = side * (1 - (Double(y) + 0.5) / Double(bitmap.pixelsHigh))
                        let nameplateTop = panel.spiritScene.childNode(withName: "//providerLabel")!.frame.maxY + 4
                        if localY < nameplateTop { continue } // Nameplate and status glyphs are decorative, outside the character target.
                        for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                            guard (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.95 else { continue }
                            visibleSamples += 1
                            let screen = CGPoint(x: panel.frame.minX + side * (Double(x) + 0.5) / Double(bitmap.pixelsWide),
                            y: panel.frame.minY + localY)
                            require(frame.contains(screen), "Rendered \(state) pixel at \(screen) is outside input area for \(side)pt")
                        }
                    }
                    require(visibleSamples > 20, "Coverage check must inspect actual rendered character pixels")
                }
            }
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let tricks = CompanionPanel(size: 128)
            tricks.spiritScene.automaticallyPlaysHammerTricks = false
            tricks.setRendering(active: true)
            tricks.spiritScene.render(state: .idle, reduceMotion: false)
            var trickTime = 1.0
            tricks.spiritScene.update(trickTime)
            for operation in 0..<3 {
                require(tricks.spiritScene.playHammerTrick(operation == 1 ? .toss : .recall),
                        "The real hammer asset must support native trick playback")
                for _ in 0..<120 where !tricks.hammerFlightPanel.isVisible {
                    trickTime += 1.0 / 60
                    tricks.spiritScene.update(trickTime)
                }
                require(tricks.hammerFlightPanel.isVisible && tricks.spiritScene.isHammerTrickPlaying,
                        "The real airborne hammer must transfer to its desktop overlay")
                switch operation {
                case 0: tricks.move(to: CGPoint(x: 100, y: 100))
                case 1: tricks.resize(to: 192)
                default: tricks.setRendering(active: false)
                }
                require(!tricks.spiritScene.isHammerTrickPlaying && !tricks.hammerFlightPanel.isVisible,
                        "Moving, resizing, and hiding must cancel the real flight and restore its grip")
            }
            tricks.close()
            tricks.interactionPanel.close()
            tricks.speechPanel.close()
            tricks.flameTrailPanel.close()
            tricks.hammerFlightPanel.close()
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let toy = CompanionPanel(size: 128)
            toy.spiritScene.tracksPointer = false
            toy.spiritScene.automaticallyPlaysHammerTricks = false
            toy.setRendering(active: true)
            toy.spiritView.isPaused = true
            toy.spiritScene.update(0)
            toy.spiritScene.render(state: .working, reduceMotion: false)
            toy.spiritScene.update(0.016)
            let held = toy.spiritScene.childNode(withName: "//heldHammer") as! SKSpriteNode
            require(held.size.width == 18 && held.size.height == 27, "Redesigned tool must load at its larger size")
            let point = held.convert(.zero, to: toy.spiritScene)
            require(toy.spiritScene.hammerContains(point), "Grip must be inside the enlarged hammer target")
            let viewPoint = toy.spiritScene.convertPoint(toView: point)
            let screenPoint = toy.convertPoint(toScreen: toy.spiritView.convert(viewPoint, to: nil))
            let eventPoint = toy.interactionPanel.convertPoint(fromScreen: screenPoint)
            var usageClicks = 0
            toy.clicked = { usageClicks += 1 }
            for count in [1, 2] {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let click = NSEvent.mouseEvent(with: type, location: eventPoint, modifierFlags: [],
                        timestamp: Double(count) * 0.1, windowNumber: toy.interactionPanel.windowNumber,
                        context: nil, eventNumber: count, clickCount: count, pressure: 1)!
                    if type == .leftMouseDown { toy.interactionPanel.interactionView.mouseDown(with: click) }
                    else { toy.interactionPanel.interactionView.mouseUp(with: click) }
                }
            }
            require(usageClicks == 0, "Hammer double-tap must not open usage")
            require(!toy.spiritScene.requestHammerToss(), "Repeated requests must not queue extra tricks")
            var sawToss = false
            for frame in 2...360 {
                if frame % 60 == 0 { toy.spiritScene.render(state: .working, reduceMotion: false) }
                toy.spiritScene.update(Double(frame) / 60)
                sawToss = sawToss || toy.spiritScene.isHammerTrickPlaying
            }
            require(sawToss && !toy.spiritScene.isHammerTrickPlaying, "Working double-tap must complete one toss")
            require(toy.spiritScene.displayedExpression == .focused, "Work must resume after user trick")
            let originalFrame = toy.frame
            let originalRecall = toy.spiritScene.hammerRecallOffset
            var clock = 6.1
            func dragHammer(left distance: CGFloat) {
                let grip = held.convert(.zero, to: toy.spiritScene)
                let view = toy.spiritScene.convertPoint(toView: grip)
                let screen = toy.convertPoint(toScreen: toy.spiritView.convert(view, to: nil))
                let origin = toy.interactionPanel.convertPoint(fromScreen: screen)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
                    let location = type == .leftMouseDown ? origin : CGPoint(x: origin.x - distance, y: origin.y)
                    let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                        timestamp: clock, windowNumber: toy.interactionPanel.windowNumber, context: nil,
                        eventNumber: 1, clickCount: 1, pressure: 1)!
                    switch type {
                    case .leftMouseDown: toy.interactionPanel.interactionView.mouseDown(with: event)
                    case .leftMouseDragged: toy.interactionPanel.interactionView.mouseDragged(with: event)
                    default: toy.interactionPanel.interactionView.mouseUp(with: event)
                    }
                    clock += 1.0 / 60
                    toy.spiritScene.update(clock)
                }
            }
            dragHammer(left: 8)
            for _ in 0..<60 { clock += 1.0 / 60; toy.spiritScene.update(clock) }
            require(toy.frame == originalFrame && !toy.spiritScene.isHammerTrickPlaying,
                    "Short hammer pull must neither move the character nor detach the hammer")
            dragHammer(left: 40)
            var sawRecall = false
            var sawSurprise = false
            for frame in 0..<420 {
                if frame % 60 == 0 { toy.spiritScene.render(state: .working, reduceMotion: false) }
                clock += 1.0 / 60
                toy.spiritScene.update(clock)
                sawRecall = sawRecall || toy.spiritScene.isHammerTrickPlaying
                sawSurprise = sawSurprise || toy.spiritScene.displayedExpression == .surprised
            }
            require(toy.frame == originalFrame && usageClicks == 0, "Hammer drag must not move the character or open usage")
            require(sawRecall && sawSurprise && !toy.spiritScene.isHammerTrickPlaying,
                    "Left hammer drag must lose, react and recall once")
            require(toy.spiritScene.hammerRecallOffset == originalRecall,
                    "User recall must restore the normal screen-dependent flight direction")
            require(toy.spiritScene.displayedExpression == .focused, "Work must resume after drag recall")
            toy.setRendering(active: false)
            toy.close(); toy.interactionPanel.close(); toy.speechPanel.close()
            toy.flameTrailPanel.close(); toy.hammerFlightPanel.close()
        }
        panel.close()
        panel.interactionPanel.close()
        panel.speechPanel.close()
        panel.flameTrailPanel.close()
        panel.hammerFlightPanel.close()
        print("PASS: native speech dismissal, visibility, left/right event routing and rendered body/head/flame coverage at 80/128/192pt")
    }
}
