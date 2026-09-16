import CoreGraphics
import Testing
@testable import SpiritCore

struct InteractionGeometryTests {
    @Test func conservativeCenterBoundsScaleWithCharacter() {
        #expect(CompanionGeometry.interactionFrame(visualOrigin: .zero, size: 80) ==
            CGRect(x: 32, y: 32, width: 16, height: 16))
        #expect(CompanionGeometry.interactionFrame(visualOrigin: .zero, size: 128) ==
            CGRect(x: 51.2, y: 51.2, width: 25.6, height: 25.6))
        #expect(CompanionGeometry.interactionFrame(visualOrigin: .zero, size: 192) ==
            CGRect(x: 76.8, y: 76.8, width: 38.4, height: 38.4))
    }

    @Test func interactionRegionFollowsWindowMovement() {
        let frame = CompanionGeometry.interactionFrame(visualOrigin: CGPoint(x: -1000, y: 200), size: 80)
        #expect(frame == CGRect(x: -968, y: 232, width: 16, height: 16))
        #expect(CGRect(x: -1000, y: 200, width: 80, height: 80).contains(frame))
    }
}
