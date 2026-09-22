import Testing
@testable import SpiritCore

@Suite("Typing response")
struct TypingActivityTests {
    @Test func requiresBurstAndExpires() {
        var input = TypingActivity()
        func sample(count: UInt32, at time: Double, enabled: Bool = true) -> Bool {
            input.sample(count: count, at: time, enabled: enabled)
        }
        #expect(!sample(count: 200, at: 0))
        #expect(!sample(count: 201, at: 0.15))
        #expect(!sample(count: 202, at: 0.3))
        #expect(sample(count: 203, at: 0.45))
        #expect(sample(count: 203, at: 1))
        #expect(!sample(count: 203, at: 1.5))
        #expect(!sample(count: 204, at: 2))
        #expect(!sample(count: 210, at: 2.1, enabled: false))
        #expect(!sample(count: 210, at: 2.2))
        #expect(sample(count: 213, at: 2.4))
    }
    @Test func responseBlendsAndYieldsToInteractions() {
        var motion = SpiritRigMotion()
        motion.setAutomaticIdleActionsEnabled(false)
        motion.setTypingActive(true)
        let first = motion.advance(by: 1.0 / 60)
        #expect(motion.typingAmount > 0 && motion.typingAmount < 0.1)
        for _ in 0..<60 { motion.advance(by: 1.0 / 60) }
        #expect(motion.typingAmount > 0.95)
        #expect(motion.pose.expression == .focused)
        #expect(abs(motion.pose.headAngle - first.headAngle) < 0.12)
        #expect(!motion.pose.didRequestHammerTrick)
        motion.setTypingActive(false)
        for _ in 0..<120 { motion.advance(by: 1.0 / 60) }
        #expect(motion.typingAmount < 0.001)
        motion.setTypingActive(true)
        motion.setDragging(true)
        motion.advance(by: 1.0 / 60)
        #expect(motion.typingAmount == 0)
        motion.setDragging(false)
        motion.setState(.working)
        motion.advance(by: 1.0 / 60)
        #expect(motion.typingAmount == 0)
        motion.advance(by: 1.0 / 60, reduceMotion: true)
        #expect(motion.typingAmount == 0)
    }
    @Test func typingDoesNotTriggerIdleHammerTricks() {
        var motion = SpiritRigMotion()
        for frame in 0..<3600 {
            if frame % 9 == 0 { motion.setTypingActive(true) }
            let pose = motion.advance(by: 1.0 / 60)
            #expect(!pose.didRequestHammerTrick)
        }
    }
}
