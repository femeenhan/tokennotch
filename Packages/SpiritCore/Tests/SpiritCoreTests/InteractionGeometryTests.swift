import CoreGraphics
import Testing
@testable import SpiritCore

struct InteractionGeometryTests {
    @Test func interactionBoundsCoverBodyHeadHammerAndFlameAtEverySize() {
        for size in [80.0, 128.0, 192.0] {
            let frame = CompanionGeometry.interactionFrame(visualOrigin: .zero, size: size)
            // Visible rig points outside the previous 20% center target.
            for point in [CGPoint(x: 0.54, y: 0.23), CGPoint(x: 0.54, y: 0.52),
                          CGPoint(x: 0.25, y: 0.45), CGPoint(x: 0.42, y: 0.83)] {
                #expect(frame.contains(CGPoint(x: point.x * size, y: point.y * size)))
            }
            #expect(!frame.contains(CGPoint(x: 0.02 * size, y: 0.02 * size)))
            #expect(!frame.contains(CGPoint(x: 0.98 * size, y: 0.98 * size)))
            #expect(CGRect(x: 0, y: 0, width: size, height: size).contains(frame))
        }
    }

    @Test func interactionRegionFollowsWindowMovement() {
        let origin = CGPoint(x: -1000, y: 200)
        let frame = CompanionGeometry.interactionFrame(visualOrigin: origin, size: 80)
        let local = CompanionGeometry.interactionFrame(visualOrigin: .zero, size: 80)
        #expect(frame == local.offsetBy(dx: origin.x, dy: origin.y))
        #expect(frame.contains(CGPoint(x: origin.x + 80 * 0.42, y: origin.y + 80 * 0.83)))
    }
}
