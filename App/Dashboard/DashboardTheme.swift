import SwiftUI
import CoreText

enum DashboardTheme {
    static func registerFonts() {
        if let url = Bundle.main.url(forResource: "neodgm", withExtension: "ttf", subdirectory: "Spirit/Fonts") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
    static func pixel(_ size: CGFloat = 16) -> Font { .system(size: size, design: .monospaced) }
    static let ink = Color(nsColor: .labelColor)
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.13, green: 0.12, blue: 0.10, alpha: 1)
            : NSColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 1)
    })
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.18, green: 0.16, blue: 0.13, alpha: 1)
            : NSColor(red: 0.985, green: 0.978, blue: 0.957, alpha: 1)
    })
    static let input = Color(red: 0.65, green: 0.44, blue: 0.27)
    static let cache = Color(red: 0.25, green: 0.59, blue: 0.29)
    static let output = Color(red: 0.87, green: 0.62, blue: 0.17)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1, green: 0.56, blue: 0.27, alpha: 1)
            : NSColor(red: 0.78, green: 0.28, blue: 0.09, alpha: 1)
    })
}

// This font's global bounding box has zero height on macOS CoreText.
// AppKit's attributed-string drawing works; SwiftUI's direct custom Text is culled.
struct PixelText: View {
    let text: String
    var size: CGFloat = 24
    @Environment(\.colorScheme) private var colorScheme
    init(_ text: String, size: CGFloat = 24) { self.text = text; self.size = size }
    var body: some View {
        let font = NSFont(name: "NeoDunggeunmo-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: colorScheme == .dark ? NSColor.white : NSColor.black])
        let extent = string.size()
        let image = NSImage(size: NSSize(width: ceil(extent.width) + 2, height: ceil(extent.height) + 4))
        let _ = render(string, into: image)
        Image(nsImage: image).interpolation(.none).accessibilityLabel(text)
    }
    private func render(_ string: NSAttributedString, into image: NSImage) {
        image.lockFocus()
        string.draw(at: NSPoint(x: 1, y: 2))
        image.unlockFocus()
    }
}

struct PixelButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 16
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 9
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(DashboardTheme.pixel(fontSize)).padding(.horizontal, horizontalPadding).padding(.vertical, verticalPadding)
            .background(configuration.isPressed ? Color.primary.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
            .overlay(Rectangle().stroke(Color.primary.opacity(0.65), lineWidth: 1))
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }
}

extension View {
    func pixelPanel() -> some View {
        padding(12).background(DashboardTheme.surface)
            .overlay(Rectangle().stroke(Color.primary.opacity(0.4), lineWidth: 2))
            .background(DashboardTheme.input.opacity(0.3).offset(x: 3, y: 3))
    }
}

// Dashboard controls and sections share one rectangular visual vocabulary.
struct DashboardButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? DashboardTheme.accent : Color.primary)
            .padding(.horizontal, 10).frame(height: 28)
            .background(selected ? DashboardTheme.accent.opacity(0.12) : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.035))
            .overlay(alignment: .bottom) {
                if selected { Rectangle().fill(DashboardTheme.accent).frame(height: 2) }
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct DashboardSectionTitle: View {
    let title: String
    var note: String? = nil
    var body: some View {
        HStack(spacing: 10) {
            PixelText(title, size: 16)
            if let note { Text(note).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
}

extension View {
    func dashboardPanel() -> some View {
        padding(14).background(DashboardTheme.surface)
            .overlay(Rectangle().stroke(Color.primary.opacity(0.14), lineWidth: 1))
    }
}
