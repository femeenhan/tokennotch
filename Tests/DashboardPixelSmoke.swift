import AppKit
import SwiftUI
import CoreText

@main
@MainActor
enum DashboardPixelSmoke {
    static func main() {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        precondition(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: PixelText("빌드정령", size: 32).preferredColorScheme(scheme).frame(width: 200, height: 60))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 60), styleMask: [], backing: .buffered, defer: false)
            window.contentView = host
            window.display()
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            var pixels = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.alphaComponent > 0.5 && (scheme == .dark ? color.redComponent > 0.8 : color.redComponent < 0.2) { pixels += 1 }
                }
            }
            precondition(pixels > 200, "Pixel title did not render: \(scheme)")
            window.contentView = nil
        }
        print("PASS: pixel Korean title renders in light and dark mode")
    }
}
