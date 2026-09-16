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
        panel.close()
        panel.interactionPanel.close()
        print("PASS: native companion left/right event routing")
    }
}
