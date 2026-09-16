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

    @Test func remainingQuotaLowersVitalityAndUnknownQuotaKeepsNormalEnergy() {
        var healthy = SpiritRigMotion()
        var depleted = SpiritRigMotion()
        var unknown = SpiritRigMotion()
        healthy.setRemainingQuota(1)
        depleted.setRemainingQuota(0.05)
        unknown.setRemainingQuota(nil)
        for _ in 0..<360 {
            _ = healthy.advance(by: 1.0 / 60)
            _ = depleted.advance(by: 1.0 / 60)
            _ = unknown.advance(by: 1.0 / 60)
        }
        #expect(depleted.pose.vitality < healthy.pose.vitality - 0.2)
        #expect(abs(unknown.pose.vitality - healthy.pose.vitality) < 0.05)
        #expect(depleted.pose.emberGlow > 0)
    }

    @Test func workBuildsHeatThatLingersAndThenSettles() {
        var motion = SpiritRigMotion()
        for _ in 0..<120 { _ = motion.advance(by: 1.0 / 60) }
        let idleHeat = motion.pose.heat
        motion.setState(.working)
        for _ in 0..<600 { _ = motion.advance(by: 1.0 / 60) }
        let workingHeat = motion.pose.heat
        #expect(workingHeat > idleHeat + 0.1)
        motion.setState(.idle)
        let firstIdle = motion.advance(by: 1.0 / 60)
        #expect(firstIdle.heat > idleHeat + 0.1)
        #expect(abs(firstIdle.heat - workingHeat) < 0.1)
        for _ in 0..<1_800 { _ = motion.advance(by: 1.0 / 60) }
        #expect(motion.pose.heat < firstIdle.heat - 0.1)
    }

    @Test func pointerAtEitherSideDrawsTheSpiritsGaze() {
        var left = SpiritRigMotion()
        var right = SpiritRigMotion()
        left.setPointer(x: -20, y: 28)
        right.setPointer(x: 20, y: 28)
        for _ in 0..<120 {
            _ = left.advance(by: 1.0 / 60)
            _ = right.advance(by: 1.0 / 60)
        }
        #expect(left.pose.gazeX < right.pose.gazeX - 0.2)
        left.setPointer(x: nil, y: nil)
        right.setPointer(x: nil, y: nil)
        for _ in 0..<600 {
            _ = left.advance(by: 1.0 / 60)
            _ = right.advance(by: 1.0 / 60)
        }
        #expect(abs(left.pose.gazeX - right.pose.gazeX) < 0.05)
    }

    @Test func quotaRecoveryAddsABriefStretchGesture() {
        var recovering = SpiritRigMotion()
        var resting = SpiritRigMotion()
        recovering.setRemainingQuota(0.05)
        resting.setRemainingQuota(0.05)
        for _ in 0..<360 {
            _ = recovering.advance(by: 1.0 / 60)
            _ = resting.advance(by: 1.0 / 60)
        }
        recovering.setRemainingQuota(1)
        var gestureDifference = 0.0
        for _ in 0..<120 {
            let recovered = recovering.advance(by: 1.0 / 60)
            let control = resting.advance(by: 1.0 / 60)
            gestureDifference = max(gestureDifference, recovered.bodyOffsetY - control.bodyOffsetY)
        }
        #expect(recovering.pose.vitality > resting.pose.vitality + 0.2)
        #expect(gestureDifference > 0.3)
    }

    @Test func completionCelebratesOnceAndAttentionOffersAnEmber() {
        var motion = SpiritRigMotion()
        motion.setState(.completed)
        let completed = (0..<180).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(completed.filter(\.didCelebrate).count == 1)
        #expect(completed.contains { $0.didEmitEmber })
        motion.setState(.attention)
        let attention = (0..<120).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(attention.contains { $0.heldEmber > 0.5 })
    }

    @Test func reducedMotionSuppressesNewEmberAndCelebrationEvents() {
        var motion = SpiritRigMotion()
        motion.setRemainingQuota(0)
        motion.setRemainingQuota(1)
        motion.setPointer(x: 0, y: -1, velocityX: 10, velocityY: 10)
        for state: SpiritState in [.working, .completed, .attention, .idle] {
            motion.setState(state)
            let first = motion.advance(by: 1.0 / 60, reduceMotion: true)
            for _ in 0..<180 {
                let next = motion.advance(by: 1.0 / 60, reduceMotion: true)
                #expect(next == first)
                #expect(!next.didStrike && !next.didCelebrate && !next.didEmitEmber)
            }
        }
    }

    @Test func invalidQuotaAndPointerInputsKeepExtendedPoseFiniteAndBounded() {
        var motion = SpiritRigMotion()
        for quota in [Double.nan, .infinity, -1, 2] {
            motion.setRemainingQuota(quota)
            motion.setPointer(x: .nan, y: .infinity, velocityX: .infinity, velocityY: .nan)
            let pose = motion.advance(by: 1.0 / 60)
            #expect([pose.heat, pose.vitality, pose.emberGlow, pose.heldEmber,
                     pose.gazeX, pose.flameSway].allSatisfy { $0.isFinite })
            #expect([pose.heat, pose.vitality, pose.emberGlow, pose.heldEmber]
                .allSatisfy { (0...1).contains($0) })
        }
    }

    @Test func passingPointerBendsFlameAndPettingSoftensEyes() {
        var still = SpiritRigMotion()
        var breezy = SpiritRigMotion()
        var petted = SpiritRigMotion()
        for _ in 0..<30 {
            breezy.setPointer(x: 40, y: 28, velocityX: 150)
            petted.setPointer(x: 0, y: 45, velocityX: 30)
            _ = still.advance(by: 1.0 / 60)
            _ = breezy.advance(by: 1.0 / 60)
            _ = petted.advance(by: 1.0 / 60)
        }
        #expect(breezy.pose.flameSway > still.pose.flameSway + 0.1)
        #expect(petted.pose.eyeOpen < still.pose.eyeOpen - 0.2)
        breezy.setPointer(x: nil, y: nil)
        for _ in 0..<300 {
            _ = still.advance(by: 1.0 / 60)
            _ = breezy.advance(by: 1.0 / 60)
        }
        #expect(abs(breezy.pose.flameSway - still.pose.flameSway) < 0.01)
    }

    @Test func idleHabitsAppearOccasionallyBeforeLongIdleSettlesToSleep() {
        var motion = SpiritRigMotion()
        let earlyIdle = (0..<3_000).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(earlyIdle.contains { $0.heldEmber > 0.5 })
        for _ in 0..<600 { _ = motion.advance(by: 1.0 / 60) }
        #expect(motion.pose.eyeOpen < 0.2)
        #expect(motion.pose.emberGlow < 0.85)
        motion.setState(.working)
        for _ in 0..<30 { _ = motion.advance(by: 1.0 / 60) }
        #expect(motion.pose.eyeOpen > 0.5)
    }
    @Test func depletedRestPreservesSilhouetteAndFinishesRaisedHammer() {
        var motion = SpiritRigMotion()
        motion.setRemainingQuota(0)
        motion.setState(.working)
        for _ in 0..<25 { _ = motion.advance(by: 1.0 / 60) }
        let raised = motion.pose.hammerAngle
        motion.setState(.sleeping)
        let first = motion.advance(by: 1.0 / 60)
        #expect(abs(first.hammerAngle - raised) < 0.15)
        let frames = (0..<360).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(frames.filter(\.didStrike).count == 1)
        #expect(frames.allSatisfy { $0.flameStretch > 0.8 && $0.bodyScaleY > 0.88 })
        #expect(motion.pose.restAmount > 0.99)
        #expect(motion.pose.hammerAngle > 0.9)
    }

    @Test func reducedMotionRetainsDesignedRestPoseWithoutAnimation() {
        var motion = SpiritRigMotion()
        motion.setRemainingQuota(0)
        let first = motion.advance(by: 0, reduceMotion: true)
        #expect(first.restAmount == 1)
        #expect(first.flameStretch == 1 && first.bodyScaleY == 1)
        for _ in 0..<30 {
            #expect(motion.advance(by: 1.0 / 60, reduceMotion: true) == first)
        }
    }

}
