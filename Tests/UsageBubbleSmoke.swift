import AppKit
import SwiftUI
import SpiritCore

@main
@MainActor
enum UsageBubbleSmoke {
    static func main() throws {
        _ = NSApplication.shared
        let rect = CGRect(x: 0, y: 0, width: 240, height: 156)
        let left = PixelSpeechBubble(tailOnLeft: true, tailY: 78).path(in: rect)
        let right = PixelSpeechBubble(tailOnLeft: false, tailY: 78).path(in: rect)
        // Offset the 6-point grid from polygon edges: boundary containment is
        // winding-direction dependent and not an interior geometry assertion.
        for x in stride(from: CGFloat(0.25), through: rect.maxX - 0.25, by: 6) {
            for y in stride(from: CGFloat(0.25), through: rect.maxY - 0.25, by: 6) {
                precondition(left.contains(CGPoint(x: x, y: y)) == right.contains(CGPoint(x: rect.maxX - x, y: y)), "Tail mirror mismatch")
            }
        }
        precondition(left.contains(CGPoint(x: 120, y: 78)), "Body must contain its center")
        precondition(!left.contains(CGPoint(x: 0, y: 0)), "Corner must remain outside")
        precondition(left.contains(CGPoint(x: 6, y: 75)), "Left tail must contain its stepped tip")
        precondition(right.contains(CGPoint(x: 234, y: 75)), "Right tail must mirror the tip")
        precondition(!left.contains(CGPoint(x: 6, y: 86)), "Tail step must exclude space beneath its tip")

        let panel = UsageBubblePanel(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        var dismissals = 0
        panel.dismiss = { dismissals += 1 }
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53)!
        panel.keyDown(with: escape)
        precondition(dismissals == 1, "Escape must invoke the dismissal callback")
        precondition(panel.canBecomeKey && !panel.canBecomeMain)

        let model = CompanionModel()
        model.quotaHasSuccessfulRead = true
        let states: [(name: String, used: Double?)] = [("", 68), ("zero", 100), ("full", 0), ("pending", nil)]
        for state in states {
        model.quota = state.used.map { used in
            QuotaSnapshot(observedAt: Date(), buckets: [QuotaBucket(id: "codex", secondary: QuotaWindow(usedPercent: used, windowDurationMins: 10080))])
        }
        for scheme in [ColorScheme.light, .dark] {
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            let host = NSHostingView(rootView: QuotaQuickView(model: model, openDashboard: {}, tailY: 78).preferredColorScheme(scheme))
            panel.contentView = host
            panel.display()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            precondition(host.bounds.size == CGSize(width: 240, height: 156), "Native usage host must be exactly 240x156; actual \(host.bounds.size)")
            precondition(host.fittingSize == CGSize(width: 240, height: 156), "Content must not demand an oversized native layout")
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            precondition((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.01, "Bubble corner must be transparent")
            let center = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!
            precondition(center.alphaComponent > 0.9, "Bubble body must be painted")
            let suffix = state.name.isEmpty ? "" : "-\(state.name)"
            let output = URL(fileURLWithPath: "/tmp/build-spirit-usage-bubble-\(scheme == .light ? "light" : "dark")\(suffix).png")
            try bitmap.representation(using: .png, properties: [:])!.write(to: output)
            panel.contentView = nil
        }
        }
        panel.close()
        print("PASS: pixel bubble mirrors in 6-point steps, body/tail/corners, native Escape, transparent light/dark rendering")
    }
}
