import Testing
@testable import SpiritCore

@Suite("Hammer tricks")
struct HammerTrickTests {
    @Test func forgeOwnsHammerUntilItsFinalRecoveryFinishes() {
        var motion = SpiritRigMotion()
        motion.setState(.working)
        for _ in 0..<20 { motion.advance(by: 1.0 / 60) }
        motion.setState(.idle)
        #expect(motion.isForging)
        for _ in 0..<120 { motion.advance(by: 1.0 / 60) }
        #expect(!motion.isForging)
        motion.setState(.working)
        motion.advance(by: 1.0 / 60, reduceMotion: true)
        #expect(!motion.isForging)
    }

    @Test func tossLeavesTheHandArcsAboveItAndReturnsAfterThreeTurns() {
        let trick = HammerTrick.toss
        let launch = trick.pose(at: trick.releaseTime)
        let apex = trick.pose(at: (trick.releaseTime + trick.catchTime) / 2)
        let landing = trick.pose(at: trick.catchTime - 0.000001)
        #expect(launch.isAirborne && apex.isAirborne)
        #expect(launch.offsetY == 0)
        #expect((54...56).contains(apex.offsetY))
        #expect(abs(landing.offsetX) < 0.001 && abs(landing.offsetY) < 0.001)
        #expect(abs(landing.rotation - launch.rotation - 6 * .pi) < 0.001)
    }

    @Test func tossIsQuickWithTrailsReservedForFastFlight() {
        let trick = HammerTrick.toss
        #expect(trick.duration == 1.55)
        #expect(trick.catchTime - trick.releaseTime < 0.85)
        let apex = trick.pose(at: (trick.releaseTime + trick.catchTime) / 2)
        #expect(apex.trailStrength < 0.1)
        #expect(trick.pose(at: trick.releaseTime + 0.07).trailStrength > 0.8)
        #expect(trick.pose(at: trick.catchTime - 0.08).trailStrength > 0.8)
        let launch = trick.pose(at: trick.releaseTime)
        #expect(abs(launch.rotation.remainder(dividingBy: 2 * .pi)) < 0.0001)
    }

    @Test func recallApproachesFromFarAwayAndArrivesAtFullSize() {
        let trick = HammerTrick.recall
        let start = trick.pose(at: trick.releaseTime)
        let middle = trick.pose(at: (trick.releaseTime + trick.catchTime) / 2)
        let end = trick.pose(at: trick.catchTime - 0.000001)
        #expect(start.offsetX >= 130 && start.offsetY >= 60)
        #expect(start.opacity == 0 && middle.opacity == 1)
        #expect(start.scale < middle.scale && middle.scale < end.scale)
        #expect(start.offsetX > middle.offsetX && middle.offsetX > end.offsetX)
        #expect(abs(end.scale - 1) < 0.001)
    }

    @Test func catchKeepsTheToolAndBodyContinuousThenSettles() {
        for trick in HammerTrick.allCases {
            let before = trick.pose(at: trick.catchTime - 0.000001)
            let caught = trick.pose(at: trick.catchTime)
            #expect(!caught.isAirborne)
            #expect(abs(before.offsetX - caught.offsetX) < 0.001)
            #expect(abs(before.offsetY - caught.offsetY) < 0.001)
            #expect(abs(before.rotation - caught.rotation) < 0.001)
            #expect(abs(before.handAngle - caught.handAngle) < 0.001)
            #expect(abs(before.bodyOffsetY - caught.bodyOffsetY) < 0.001)
            #expect(abs(before.bodyScaleY - caught.bodyScaleY) < 0.001)
            #expect(trick.pose(at: trick.catchTime + 0.1).bodyScaleY < 1)
            #expect(trick.pose(at: trick.duration) == HammerTrickPose())
        }
    }

    @Test func invalidAndOutsideTimesHaveSafeNeutralPoses() {
        for trick in HammerTrick.allCases {
            for time in [Double.nan, .infinity, -.infinity, -1, 0, trick.duration, trick.duration + 10] {
                #expect(trick.pose(at: time) == HammerTrickPose())
            }
            for frame in 0...240 {
                let pose = trick.pose(at: Double(frame) / 100)
                #expect([pose.offsetX, pose.offsetY, pose.rotation, pose.scale,
                         pose.opacity, pose.handAngle, pose.bodyOffsetY, pose.bodyScaleY,
                         pose.headAngle, pose.gazeX, pose.gazeY].allSatisfy { $0.isFinite })
                #expect((0...1).contains(pose.opacity))
                #expect((0.4...1).contains(pose.scale))
                #expect((0.9...1.05).contains(pose.bodyScaleY))
            }
        }
    }
}

@Suite("Hammer key poses")
struct HammerKeyPoseTests {
    @Test func recallTurnsItsWholeBodyAndWaitsWithAStableReach() {
        let early = HammerTrick.recall.pose(at: 0.15)
        let wait = HammerTrick.recall.pose(at: 0.55)
        let lateWait = HammerTrick.recall.pose(at: 0.85)
        #expect(wait.bodyOffsetX > early.bodyOffsetX + 1)
        #expect(wait.turnAmount == 1 && lateWait.turnAmount == 1)
        #expect(wait.reachAmount == 1 && lateWait.reachAmount == 1)
        #expect(wait.bodyAngle < -0.07)
        #expect(wait.headOffsetX > 0.5)
        #expect(abs(wait.bodyOffsetX - lateWait.bodyOffsetX) < 0.05)
        let catchPose = HammerTrick.recall.pose(at: 1.5)
        let recoil = HammerTrick.recall.pose(at: 1.64)
        #expect(recoil.bodyOffsetX < catchPose.bodyOffsetX - 1)
        #expect(recoil.bodyScaleY < 0.96)
        #expect(recoil.reachAmount < catchPose.reachAmount)
    }

    @Test func tossHasAVisibleCrouchAndLiftBeforeTheToolLeaves() {
        let crouch = HammerTrick.toss.pose(at: 0.16)
        let release = HammerTrick.toss.pose(at: HammerTrick.toss.releaseTime)
        #expect(crouch.bodyOffsetY < -0.8)
        #expect(release.bodyOffsetY > 0.8)
        #expect(release.headOffsetY > 0)
        #expect(HammerTrick.toss.pose(at: 0.8).gazeY > 0.7)
    }

    @Test func extendedPoseChannelsStayFiniteAndContinuous() {
        for trick in HammerTrick.allCases {
            var previous = trick.pose(at: 0)
            for frame in 1...Int(trick.duration * 1000) {
                let pose = trick.pose(at: Double(frame) / 1000)
                let channels = [pose.bodyOffsetX, pose.bodyAngle, pose.turnAmount,
                                pose.reachAmount, pose.freeArmAngle, pose.headOffsetX,
                                pose.headOffsetY, pose.headScaleX, pose.catchGlow, pose.trailStrength]
                #expect(channels.allSatisfy { $0.isFinite })
                #expect((0...1).contains(pose.turnAmount) && (0...1).contains(pose.reachAmount))
                #expect((0...0.25).contains(pose.catchGlow))
                #expect(abs(pose.bodyOffsetX - previous.bodyOffsetX) < 0.1)
                #expect(abs(pose.bodyOffsetY - previous.bodyOffsetY) < 0.1)
                #expect(abs(pose.handAngle - previous.handAngle) < 0.1)
                previous = pose
            }
            #expect(trick.pose(at: trick.duration - 0.000001).turnAmount < 0.001)
            #expect(trick.pose(at: trick.catchTime - 0.1).trailStrength > 0)
        }
    }
}
