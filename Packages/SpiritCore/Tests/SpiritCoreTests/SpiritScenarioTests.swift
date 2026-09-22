import Testing
@testable import SpiritCore

@Suite("Authored character scenarios")
struct SpiritScenarioTests {
    private func advance(_ motion: inout SpiritRigMotion, _ seconds: Double, fps: Int = 60) -> [SpiritRigPose] {
        (0..<Int((seconds * Double(fps)).rounded())).map { _ in motion.advance(by: 1 / Double(fps)) }
    }
    @Test func gazeLeadsHeadAndClearsOnLeave() {
        var motion = SpiritRigMotion()
        motion.setPointer(x: 25, y: 30)
        let early = advance(&motion, 0.15).last!
        #expect(early.gazeX > 0.5)
        #expect(abs(early.headAngle) < 0.02)
        #expect(advance(&motion, 0.5).last!.headAngle > 0.04)
        motion.setPointer(x: nil, y: nil)
        #expect(abs(advance(&motion, 0.5).last!.gazeX) < 0.1)
    }
    @Test func pettingRetainsAfterglowThenOpensEyes() {
        var motion = SpiritRigMotion()
        motion.setPointer(x: 8, y: 45, velocityX: 30)
        _ = advance(&motion, 1)
        motion.setPointer(x: nil, y: nil)
        #expect(advance(&motion, 0.3).last!.expression == .content)
        let opening = advance(&motion, 0.3).last!
        #expect(opening.eyeReopen > 0 && opening.eyeReopen < 1)
        #expect(advance(&motion, 0.5).last!.expression == .neutral)
    }
    @Test func completionInspectsThenJumpsAndNeverQueuesDuringDrag() {
        var motion = SpiritRigMotion()
        motion.setState(.completed)
        #expect(advance(&motion, 0.6).allSatisfy { !$0.didCelebrate && $0.bodyOffsetY < 1 })
        #expect(advance(&motion, 0.6).filter(\.didCelebrate).count == 1)
        motion.setState(.idle)
        motion.setDragging(true)
        motion.setState(.completed)
        _ = advance(&motion, 1)
        motion.setDragging(false)
        #expect(advance(&motion, 4).allSatisfy { !$0.didCelebrate })
    }
    @Test func emberHasAnIndependentPathAndYieldsToInput() {
        var motion = SpiritRigMotion()
        let started = motion.playEmberPlay()
        #expect(started)
        let rise = advance(&motion, 1.3)
        #expect(rise.last!.playEmberY > rise.first!.playEmberY + 3)
        #expect(advance(&motion, 1).last!.expression == .proud)
        motion.beginPress()
        #expect(advance(&motion, 0.1).allSatisfy { $0.playEmberOpacity == 0 })
    }
    @Test func attentionAndErrorRemainDistinctIncludingReducedMotion() {
        var motion = SpiritRigMotion()
        motion.setState(.attention)
        #expect(advance(&motion, 2).last!.expression == .requesting)
        motion.setState(.error)
        #expect(advance(&motion, 2).last!.expression == .worried)
        #expect(motion.advance(by: 0, reduceMotion: true).expression == .worried)
    }
    @Test func restYawnsBeforeSleepingAndWakesEyesFirst() {
        var motion = SpiritRigMotion()
        motion.setState(.sleeping)
        #expect(advance(&motion, 1.5).contains { $0.expression == .yawning })
        #expect(advance(&motion, 2).last!.restAmount > 0.99)
        motion.setState(.idle)
        motion.beginPress()
        let waking = advance(&motion, 0.1).last!
        #expect(waking.eyeOpen > 0.7 && waking.restAmount > 0.4)
        #expect(advance(&motion, 0.5).last!.restAmount < 0.01)
    }
    @Test func workUsesLightLightHeavyAndFatigueSlowsCadence() {
        func strikes(quota: Double, fps: Int) -> [Double] {
            var motion = SpiritRigMotion()
            motion.setRemainingQuota(quota)
            motion.setState(.working)
            return advance(&motion, 12, fps: fps).filter(\.didStrike).map(\.strikeStrength)
        }
        let healthy = strikes(quota: 1, fps: 60)
        #expect(healthy.count > 3)
        #expect(healthy[0] < healthy[2] && healthy[1] < healthy[2])
        #expect(strikes(quota: 0.05, fps: 60).count < healthy.count)
        #expect(strikes(quota: 1, fps: 30) == strikes(quota: 1, fps: 120))
    }
    @Test func idleSchedulerWaitsAndCancelDoesNotLandOrResumeCompletion() {
        var motion = SpiritRigMotion()
        #expect(advance(&motion, 24).allSatisfy { $0.playEmberOpacity == 0 && !$0.didRequestHammerTrick })
        #expect(advance(&motion, 4).contains { $0.playEmberOpacity > 0.5 })
        motion.setDragging(true)
        _ = advance(&motion, 0.5)
        motion.setState(.completed)
        motion.cancelInteractions()
        let frames = advance(&motion, 4)
        #expect(frames.allSatisfy { !$0.didCelebrate && abs($0.bodyScaleY - 1) < 0.02 })
    }
    @Test func sleepCompletionAndReducedMotionNeverReplayLargeActions() {
        var motion = SpiritRigMotion()
        motion.setState(.sleeping)
        _ = advance(&motion, 0.1)
        motion.setState(.completed)
        #expect(advance(&motion, 4).allSatisfy { !$0.didCelebrate })
        motion.setState(.idle)
        _ = motion.playEmberPlay()
        let reduced = motion.advance(by: 0.02, reduceMotion: true)
        #expect(reduced.playEmberOpacity == 0 && !reduced.didRequestHammerTrick)
        #expect(advance(&motion, 4).allSatisfy { $0.playEmberOpacity == 0 })
    }
    @Test func gazeCooldownPreventsAnotherHeadTurn() {
        var motion = SpiritRigMotion()
        motion.setPointer(x: 25, y: 28)
        _ = advance(&motion, 0.6)
        motion.setPointer(x: nil, y: nil)
        _ = advance(&motion, 0.2)
        motion.setPointer(x: -25, y: 28)
        let cooling = advance(&motion, 0.6).last!
        #expect(cooling.gazeX < -1 && abs(cooling.headAngle) < 0.02)
    }

    @Test func pettingDirectionChangesKeepContentAndStoppedDragSettles() {
        var motion = SpiritRigMotion()
        motion.setPointer(x: 8, y: 45, velocityX: 30)
        _ = advance(&motion, 1)
        motion.setPointer(x: 8, y: 45)
        _ = advance(&motion, 0.08)
        motion.setPointer(x: 8, y: 45, velocityX: -30)
        #expect(advance(&motion, 0.02).last!.expression == .content)
        motion.setDragging(true)
        for _ in 0..<30 {
            motion.setDragVelocity(x: 200, y: 80)
            _ = motion.advance(by: 1.0 / 60)
        }
        #expect(abs(motion.pose.dragLean) > 0.1)
        let stopped = advance(&motion, 1).last!
        #expect(abs(stopped.dragLean) < 0.01 && stopped.bodyScaleY > 1.1)
        motion.cancelInteractions()
        #expect(motion.pose.bodyScaleY == 1 && motion.pose.playEmberOpacity == 0)
    }
    @Test func lowEnergyCompletionIsProudWithoutJump() {
        var motion = SpiritRigMotion()
        motion.setRemainingQuota(0.05)
        motion.setState(.completed)
        let frames = advance(&motion, 4)
        #expect(frames.allSatisfy { !$0.didCelebrate && $0.bodyOffsetY < 1 && $0.expression == .proud })
    }

    @Test func urgentStateImmediatelyOverridesPettingAfterglow() {
        for state: SpiritState in [.error, .attention] {
            var motion = SpiritRigMotion()
            motion.setPointer(x: 8, y: 45, velocityX: 30)
            _ = advance(&motion, 1)
            motion.setState(state)
            let first = motion.advance(by: 1.0 / 60)
            #expect(first.expression == (state == .error ? .surprised : .requesting))
            #expect(advance(&motion, 1).allSatisfy { $0.expression != .content })
        }
    }

}
