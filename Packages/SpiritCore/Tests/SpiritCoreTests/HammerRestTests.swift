import Testing
@testable import SpiritCore

@Suite("Grounded hammer rest")
struct HammerRestTests {
    @Test func idleAndTypingKeepHammerGrounded() {
        var motion = SpiritRigMotion()
        #expect(motion.pose.hammerRest == 1)
        motion.setAutomaticIdleActionsEnabled(false)
        motion.setTypingActive(true)
        for _ in 0..<180 {
            #expect(motion.advance(by: 1.0 / 60).hammerRest == 1)
        }
        #expect(motion.typingAmount > 0.9)
        motion.setState(.sleeping)
        #expect(motion.advance(by: 1.0 / 60).hammerRest == 1)
    }

    @Test func workLiftsBeforeWindupAndFinishesRecoveryBeforeLowering() {
        var motion = SpiritRigMotion()
        motion.setState(.working)
        let lift = (0..<30).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(lift.first!.hammerRest > 0.9)
        #expect(lift.last!.hammerRest == 0)
        #expect(lift.allSatisfy { !$0.didStrike && $0.hammerAngle == 0 })
        #expect(zip(lift, lift.dropFirst()).allSatisfy { $0.hammerRest >= $1.hammerRest })
        for _ in 0..<50 { _ = motion.advance(by: 1.0 / 60) }
        motion.setState(.idle)
        var recovered = false
        for _ in 0..<180 {
            let pose = motion.advance(by: 1.0 / 60)
            if motion.isForging { #expect(pose.hammerRest == 0) }
            else { recovered = true }
        }
        #expect(recovered)
        #expect(motion.pose.hammerRest == 1)
    }

    @Test func directInteractionsLiftAndCancellationPreservesTransition() {
        var motion = SpiritRigMotion()
        motion.setIdleActionActive(true)
        for _ in 0..<12 { _ = motion.advance(by: 1.0 / 60) }
        let partial = motion.pose.hammerRest
        #expect(partial > 0 && partial < 1)
        motion.cancelInteractions()
        #expect(motion.pose.hammerRest == partial)
        for _ in 0..<30 { _ = motion.advance(by: 1.0 / 60) }
        #expect(motion.pose.hammerRest == 1)
        motion.beginPress()
        for _ in 0..<30 { _ = motion.advance(by: 1.0 / 60) }
        #expect(motion.pose.hammerRest == 0)
    }

    @Test func reducedMotionUsesStaticGroundedOrReadyPose() {
        var motion = SpiritRigMotion()
        #expect(motion.advance(by: 0, reduceMotion: true).hammerRest == 1)
        motion.setState(.working)
        #expect(motion.advance(by: 0, reduceMotion: true).hammerRest == 0)
        motion.setState(.idle)
        #expect(motion.advance(by: 0, reduceMotion: true).hammerRest == 1)
        motion.setIdleActionActive(true)
        #expect(motion.advance(by: 0, reduceMotion: true).hammerRest == 0)
    }
}
