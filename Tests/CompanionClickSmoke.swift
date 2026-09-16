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
        var interactionTime = 1.0
        panel.spiritScene.update(interactionTime)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            if type == .leftMouseDown {
                for _ in 0..<60 {
                    interactionTime += 1.0 / 60
                    panel.spiritScene.update(interactionTime)
                }
            }
            guard let event = NSEvent.mouseEvent(with: type,
                location: CGPoint(x: input.bounds.midX, y: input.bounds.midY),
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
        require(panel.speechPanel.isVisible && panel.speechPanel.speechView.message == "다 만들었어!",
                "Completion dialogue must remain until tapped after its brief pose ends")
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
        require(panel.flameTrailPanel.ignoresMouseEvents && !panel.flameTrailPanel.canBecomeKey,
                "Decorative drag flames must neither capture clicks nor activate")
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
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
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            require(trailScene.children.isEmpty && !panel.flameTrailPanel.isVisible,
                    "External flames must expire and hide their window automatically")
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
                        let nameplateTop = panel.spiritScene.childNode(withName: "providerLabel")!.frame.maxY + 4
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
        panel.close()
        panel.interactionPanel.close()
        panel.speechPanel.close()
        panel.flameTrailPanel.close()
        print("PASS: native speech dismissal, visibility, left/right event routing and rendered body/head/flame coverage at 80/128/192pt")
    }
}
