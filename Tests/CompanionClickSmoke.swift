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
        func event(_ type: NSEvent.EventType) -> NSEvent {
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
                        if localY < side * 0.12 { continue } // Exclude the separate name label below the character.
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
        print("PASS: native left/right event routing and rendered body/head/flame coverage at 80/128/192pt")
    }
}
