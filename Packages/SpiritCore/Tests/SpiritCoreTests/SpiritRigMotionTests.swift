import Testing
@testable import SpiritCore

@Suite("Procedural spirit rig")
struct SpiritRigMotionTests {
    @Test func idleKeepsHammerStillWhileFlameBreathAndEyesMove() {
        var motion = SpiritRigMotion()
        let frames = (0..<600).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(frames.allSatisfy { $0.hammerAngle == 0 && !$0.didStrike })
        #expect(frames.contains { $0.eyeOpen < 0.2 })
        #expect(Set(frames.map(\.flameSway)).count > 100)
        #expect(Set(frames.map(\.bodyScaleY)).count > 100)
    }

    @Test func workingWindsUpStrikesOnceAndRecovers() {
        var motion = SpiritRigMotion()
        motion.setState(.working)
        let frames = (0..<90).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(frames.contains { $0.hammerAngle < -0.5 })
        #expect(frames.contains { $0.hammerAngle > 1 })
        #expect(frames.filter(\.didStrike).count == 1)
        #expect(frames.contains { $0.impact > 0.8 && $0.bodyOffsetY < -0.5 })
        #expect(abs(frames.last!.hammerAngle) < 0.1)
    }

    @Test func leavingWorkFinishesCurrentSwingWithoutSnappingOrRestarting() {
        var motion = SpiritRigMotion()
        motion.setState(.working)
        for _ in 0..<25 { _ = motion.advance(by: 1.0 / 60) }
        let before = motion.pose
        motion.setState(.idle)
        #expect(motion.pose == before)
        let frames = (0..<180).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(abs(frames[0].hammerAngle - before.hammerAngle) < 0.15)
        #expect(frames.filter(\.didStrike).count == 1)
        #expect(frames.last!.hammerAngle == 0)
    }

    @Test func repeatedWorkingEventsDoNotRestartSwing() {
        var motion = SpiritRigMotion()
        var strikes = 0
        for _ in 0..<180 {
            motion.setState(.working)
            if motion.advance(by: 1.0 / 60).didStrike { strikes += 1 }
        }
        #expect(strikes == 2)
    }

    @Test func reducedMotionIsStaticAndProducesNoStrikes() {
        var motion = SpiritRigMotion()
        motion.setState(.working)
        let first = motion.advance(by: 1.0 / 60, reduceMotion: true)
        for _ in 0..<180 {
            #expect(motion.advance(by: 1.0 / 60, reduceMotion: true) == first)
        }
        #expect(!first.didStrike)
    }

    @Test func resumeDeltaIsClampedAndInvalidDeltasAreHarmless() {
        var motion = SpiritRigMotion()
        motion.setState(.working)
        let pose = motion.advance(by: 3_600)
        #expect(!pose.didStrike)
        #expect(abs(pose.hammerAngle) < 0.15)
        for delta in [Double.nan, .infinity, -1, 0] {
            let next = motion.advance(by: delta)
            #expect(next == pose)
        }
    }

    @Test func everyStateProducesFiniteBoundedPoses() {
        var motion = SpiritRigMotion()
        for state: SpiritState in [.working, .idle, .attention, .completed, .error, .greeting, .sleeping] {
            motion.setState(state)
            for _ in 0..<240 {
                let p = motion.advance(by: 1.0 / 60)
                #expect([p.hammerAngle, p.bodyOffsetY, p.bodyScaleY, p.headAngle,
                         p.flameSway, p.flameStretch, p.eyeOpen, p.gazeX,
                         p.freeArmAngle, p.impact].allSatisfy { $0.isFinite })
                #expect((0...1).contains(p.impact) && (0...1).contains(p.eyeOpen))
            }
        }
    }

    @Test func existingFeedbackStatesRetainTheirOwnGestureWithoutSnapping() {
        for state: SpiritState in [.attention, .completed, .error, .greeting] {
            var idle = SpiritRigMotion()
            var feedback = SpiritRigMotion()
            for _ in 0..<30 {
                _ = idle.advance(by: 1.0 / 60)
                _ = feedback.advance(by: 1.0 / 60)
            }
            let before = feedback.pose
            feedback.setState(state)
            #expect(feedback.pose == before)
            let first = feedback.advance(by: 1.0 / 60)
            #expect(abs(first.headAngle - before.headAngle) < 0.05)
            #expect(abs(first.bodyOffsetY - before.bodyOffsetY) < 0.3)
            for _ in 0..<14 { _ = feedback.advance(by: 1.0 / 60) }
            for _ in 0..<15 { _ = idle.advance(by: 1.0 / 60) }
            #expect(abs(feedback.pose.headAngle - idle.pose.headAngle)
                    + abs(feedback.pose.bodyOffsetY - idle.pose.bodyOffsetY)
                    + abs(feedback.pose.freeArmAngle - idle.pose.freeArmAngle) > 0.1)
            let active = feedback.pose
            feedback.setState(.idle)
            let settling = feedback.advance(by: 1.0 / 60)
            #expect(abs(settling.headAngle - active.headAngle) < 0.05)
            #expect(abs(settling.bodyOffsetY - active.bodyOffsetY) < 0.3)
        }
    }
}
