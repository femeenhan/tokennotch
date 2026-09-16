import Foundation
import Testing
@testable import SpiritCore

struct UsageBubblePlacementTests {
    @Test func explicitCompactSizePreservesAnchorAndFlipsAtRightEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 240, height: 156)
        let right = UsageBubblePlacement.place(characterFrame: CGRect(x: 100, y: 300, width: 80, height: 100), visibleFrames: [screen], size: size)
        #expect(right.frame == CGRect(x: 186, y: 272, width: 240, height: 156))
        #expect(right.tailOnLeft)
        #expect(right.tailYFromTop == 78)
        let left = UsageBubblePlacement.place(characterFrame: CGRect(x: 880, y: 300, width: 80, height: 100), visibleFrames: [screen], size: size)
        #expect(left.frame == CGRect(x: 634, y: 272, width: 240, height: 156))
        #expect(!left.tailOnLeft)
        #expect(left.tailYFromTop == 78)
    }

    @Test func prefersRightWithSixPointGapAndVerticallyCenteredTail() {
        let result = UsageBubblePlacement.place(characterFrame: CGRect(x: 100, y: 300, width: 80, height: 100), visibleFrames: [CGRect(x: 0, y: 0, width: 1000, height: 800)])
        #expect(result.frame == CGRect(x: 186, y: 250, width: 320, height: 200))
        #expect(result.tailOnLeft)
        #expect(result.tailYFromTop == 100)
    }

    @Test func nearRightEdgeUsesLeftAndTailPointsRight() {
        let result = UsageBubblePlacement.place(characterFrame: CGRect(x: 880, y: 300, width: 80, height: 100), visibleFrames: [CGRect(x: 0, y: 0, width: 1000, height: 800)])
        #expect(result.frame == CGRect(x: 554, y: 250, width: 320, height: 200))
        #expect(!result.tailOnLeft)
    }

    @Test func selectsNegativeOriginMonitorContainingCharacterCenter() {
        let result = UsageBubblePlacement.place(characterFrame: CGRect(x: -900, y: 300, width: 80, height: 100), visibleFrames: [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: -1000, y: 100, width: 1000, height: 700)])
        #expect(result.frame == CGRect(x: -814, y: 250, width: 320, height: 200))
        #expect(result.tailOnLeft)
    }

    @Test func clampsTopAndBottomWhileTailTargetsCharacterFromTop() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let top = UsageBubblePlacement.place(characterFrame: CGRect(x: 100, y: 750, width: 80, height: 40), visibleFrames: [screen])
        #expect(top.frame.minY == 592)
        #expect(top.tailYFromTop == 24)
        let bottom = UsageBubblePlacement.place(characterFrame: CGRect(x: 100, y: 10, width: 80, height: 40), visibleFrames: [screen])
        #expect(bottom.frame.minY == 8)
        #expect(bottom.tailYFromTop == 176)
    }

    @Test func insufficientSpaceChoosesLargerSideAndClampsInsidePadding() {
        let result = UsageBubblePlacement.place(characterFrame: CGRect(x: 300, y: 100, width: 80, height: 100), visibleFrames: [CGRect(x: 0, y: 0, width: 600, height: 400)])
        #expect(!result.tailOnLeft)
        #expect(result.frame == CGRect(x: 8, y: 50, width: 320, height: 200))
    }

    @Test func absentCenterMatchChoosesGreatestIntersectionThenFirstScreenFallback() {
        let screens = [CGRect(x: 0, y: 0, width: 300, height: 300), CGRect(x: 400, y: 0, width: 300, height: 300)]
        let overlap = UsageBubblePlacement.place(characterFrame: CGRect(x: 240, y: 100, width: 260, height: 100), visibleFrames: screens)
        #expect(overlap.frame == CGRect(x: 408, y: 50, width: 284, height: 200))
        let outside = UsageBubblePlacement.place(characterFrame: CGRect(x: 900, y: 900, width: 20, height: 20), visibleFrames: screens)
        #expect(outside.frame == CGRect(x: 8, y: 92, width: 284, height: 200))
    }

    @Test func tinyScreenClampsSizeAndTailWithoutInvertedBounds() {
        let result = UsageBubblePlacement.place(characterFrame: CGRect(x: -5, y: -5, width: 10, height: 10), visibleFrames: [CGRect(x: -10, y: -10, width: 30, height: 40)])
        #expect(result.frame == CGRect(x: -2, y: -2, width: 14, height: 24))
        #expect(result.tailYFromTop == 12)
        let smallest = UsageBubblePlacement.place(characterFrame: .zero, visibleFrames: [CGRect(x: 0, y: 0, width: 10, height: 10)])
        #expect(smallest.frame == CGRect(x: 5, y: 5, width: 0, height: 0))
        #expect(smallest.tailYFromTop == 0)
    }
}
