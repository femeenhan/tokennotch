import AppKit
import SwiftUI
import SpiritCore

@main
@MainActor
enum UsageBubbleSmoke {
    static func main() throws {
        _ = NSApplication.shared
        let rect = CGRect(origin: .zero, size: QuotaQuickView.size)
        let left = SpiritSpeechView.bubblePath(size: rect.size, tailOnLeft: true, tailY: 48)
        let right = SpiritSpeechView.bubblePath(size: rect.size, tailOnLeft: false, tailY: 48)
        for x in stride(from: CGFloat(0.25), through: rect.maxX - 0.25, by: 2) {
            for y in stride(from: CGFloat(0.25), through: rect.maxY - 0.25, by: 2) {
                precondition(left.contains(CGPoint(x: x, y: y)) == right.contains(CGPoint(x: rect.maxX - x, y: y)), "Tail mirror mismatch")
            }
        }
        precondition(left.contains(CGPoint(x: rect.midX, y: rect.midY)))
        precondition(!left.contains(.zero))
        precondition(left.contains(CGPoint(x: 5, y: 48)))
        precondition(right.contains(CGPoint(x: rect.maxX - 5, y: 48)))

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
        let states: [(name: String, used: Double?)] = [("", 68), ("zero", 100), ("full", 0), ("decimal", 0.1), ("stale", 68), ("pending", nil)]
        for state in states {
        model.quota = state.used.map { used in
            QuotaSnapshot(observedAt: Date().addingTimeInterval(state.name == "stale" ? -600 : 0), buckets: [QuotaBucket(id: "codex", secondary: QuotaWindow(usedPercent: used, windowDurationMins: 10080))])
        }
        for scheme in [ColorScheme.light, .dark] {
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
            let host = NSHostingView(rootView: QuotaQuickView(model: model, openDashboard: {}, tailY: 48).preferredColorScheme(scheme))
            panel.contentView = host
            panel.display()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            precondition(host.bounds.size == QuotaQuickView.size, "Native usage host must be exactly 188x96; actual \(host.bounds.size)")
            precondition(host.fittingSize == QuotaQuickView.size, "Content must not demand an oversized native layout")
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
        print("PASS: shared rounded bubble geometry, compact layout, native Escape, transparent light/dark rendering across quota states")
    }
}
