import Foundation
import CoreGraphics

public enum CompanionGeometry {
    public static func interactionFrame(visualOrigin: CGPoint, size: Double) -> CGRect {
        let side = clampedSize(size)
        // Cover the cutout rig's body, head, flame and moving hammer with a small margin.
        // Keep the outer window corners click-through; a 20% center target missed visible parts.
        return CGRect(x: visualOrigin.x + side * 0.10, y: visualOrigin.y + side * 0.10,
                      width: side * 0.80, height: side * 0.85)
    }

    public static func clampedSize(_ size: Double) -> Double {
        size.isFinite ? min(192, max(80, size)) : 128
    }

    public static func safeOrigin(_ origin: CGPoint?, size: Double,
                                  visibleFrames: [CGRect], primaryFrame: CGRect) -> CGPoint {
        let side = clampedSize(size)
        let validOrigin = origin.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil }
        let frame = validOrigin.flatMap { point in
            visibleFrames.first { $0.contains(point) }
        } ?? primaryFrame
        let safe = frame.insetBy(dx: 16, dy: 16)
        let fallback = CGPoint(x: max(safe.minX, safe.maxX - side), y: safe.minY)
        guard let point = validOrigin, visibleFrames.contains(where: { $0.contains(point) }) else {
            return fallback
        }
        return CGPoint(x: min(max(safe.minX, point.x), max(safe.minX, safe.maxX - side)),
                       y: min(max(safe.minY, point.y), max(safe.minY, safe.maxY - side)))
    }
}
