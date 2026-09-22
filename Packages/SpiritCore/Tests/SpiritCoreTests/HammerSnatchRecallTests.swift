import Testing
@testable import SpiritCore

@Suite("Hammer snatch recall")
struct HammerSnatchRecallTests {
    @Test func departureStartsAtTheHandAndPausesBeforeReturning() {
        let trick = HammerTrick.snatchRecall
        let start = trick.pose(at: 0.000001)
        #expect(start.isAirborne)
        #expect(abs(start.offsetX) < 0.001 && abs(start.offsetY) < 0.001)
        #expect(abs(start.rotation) < 0.001)
        let away = trick.pose(at: 0.35)
        let waiting = trick.pose(at: 0.65)
        #expect(away.offsetX == 140 && waiting.offsetX == 140)
        #expect(away.rotation == waiting.rotation)
        #expect(waiting.trailStrength == 0)
        #expect(waiting.turnAmount == 0)
        #expect(trick.pose(at: 1.1).turnAmount > 0.99)
    }

    @Test func returningAcceleratesAndMaintainsFullSizeUntilCatch() {
        let trick = HammerTrick.snatchRecall
        let earlyDistance = trick.pose(at: 0.9).offsetX - trick.pose(at: 1.0).offsetX
        let lateDistance = trick.pose(at: 1.7).offsetX - trick.pose(at: 1.8).offsetX
        #expect(lateDistance > earlyDistance * 3)
        for frame in 1..<190 {
            let pose = trick.pose(at: Double(frame) / 100)
            #expect(pose.scale == 1 && pose.opacity == 1)
            #expect(pose.offsetX >= 0 && pose.offsetX <= 140)
        }
        let impact = trick.pose(at: trick.catchTime + 0.14)
        #expect(impact.bodyScaleY < 0.93)
        #expect(impact.bodyOffsetY < -1.4)
        #expect(trick.pose(at: trick.duration) == HammerTrickPose())
    }
}
