import Testing
@testable import SpiritCore

@Suite("Procedural spirit rig")
struct SpiritRigMotionTests {
    @Test func draggingDuringCompletionDoesNotResumeAnInterruptedJump() {
        var motion = SpiritRigMotion()
        motion.setState(.completed)
        for _ in 0..<60 { _ = motion.advance(by: 1.0 / 60) }
        #expect(motion.pose.bodyOffsetY > 2)
        motion.setDragging(true)
        for _ in 0..<60 { _ = motion.advance(by: 1.0 / 60) }
        motion.setDragging(false)
        let afterRelease = (0..<120).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(afterRelease.allSatisfy { $0.expression != .proud })
        #expect(afterRelease.allSatisfy { $0.bodyOffsetY < 1 })
    }

    @Test func heldDragStretchesEvenWhenPointerStopsAndReleaseSettles() {
        var motion = SpiritRigMotion()
        motion.setDragging(true)
        motion.setDragVelocity(x: 180, y: 120)
        for _ in 0..<30 { _ = motion.advance(by: 1.0 / 60) }
        motion.setDragVelocity(x: 0, y: 0)
        for _ in 0..<30 { _ = motion.advance(by: 1.0 / 60) }
        #expect(motion.pose.expression == .surprised)
        #expect(motion.pose.bodyScaleY > 1.12)
        #expect(motion.pose.bodyScaleX < 0.96)
        #expect(!motion.canPlayIdleAction)
        motion.setDragging(false)
        let released = (0..<180).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(released.contains { $0.bodyScaleY < 0.99 })
        #expect(abs(released.last!.bodyScaleY - 1) < 0.02)
        #expect(released.last!.expression == .neutral)
        #expect(motion.canPlayIdleAction)
    }

    @Test func idleActionsYieldToPettingAndDoNotStackHabits() {
        var motion = SpiritRigMotion()
        #expect(motion.canPlayIdleAction)
        motion.setIdleActionActive(true)
        let reserved = (0..<900).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(reserved.allSatisfy { $0.heldEmber == 0 && $0.mouthOpen == 1 })
        #expect(!motion.canPlayIdleAction)
        motion.setIdleActionActive(false)
        motion.setPointer(x: 8, y: 45, velocityX: 30)
        #expect(!motion.canPlayIdleAction)
        for _ in 0..<60 { _ = motion.advance(by: 1.0 / 60) }
        #expect(motion.pose.expression == .content)
        #expect(motion.pose.heldEmber == 0)
    }

    @Test func interruptedCompletionDoesNotCelebrateDuringNewWork() {
        var motion = SpiritRigMotion()
        motion.setState(.completed)
        for _ in 0..<10 { _ = motion.advance(by: 1.0 / 60) }
        motion.setState(.working)
        let frames = (0..<180).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(frames.allSatisfy { !$0.didCelebrate && $0.expression != .proud })
        #expect(frames.filter(\.didStrike).count == 2)
    }

    @Test func pettingShowsContentmentInsteadOfFatigueAndRelaxesAfterLeaving() {
        var motion = SpiritRigMotion()
        for _ in 0..<60 {
            motion.setPointer(x: 8, y: 45, velocityX: 30)
            _ = motion.advance(by: 1.0 / 60)
        }
        #expect(motion.pose.expression == .content)
        #expect(motion.pose.bodyScaleX > 1.03)
        #expect(motion.pose.bodyScaleY < 0.97)
        motion.setPointer(x: nil, y: nil)
        for _ in 0..<300 { _ = motion.advance(by: 1.0 / 60) }
        #expect(motion.pose.expression == .neutral)
        #expect(abs(motion.pose.bodyScaleX - 1) < 0.02)
    }

    @Test func completionLooksProudThenReturnsToNeutralWithoutRepeating() {
        var motion = SpiritRigMotion()
        motion.setState(.completed)
        let frames = (0..<240).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(frames.contains { $0.expression == .focused })
        #expect(frames.contains { $0.expression == .proud })
        #expect(frames.contains { $0.bodyScaleY < 0.94 })
        #expect(frames.contains { $0.bodyOffsetY > 2 })
        #expect(frames.filter(\.didCelebrate).count == 1)
        #expect(frames.last!.expression == .neutral)
    }

    @Test func completionWaitsForTheLastHammerStrokeBeforeCelebrating() {
        var motion = SpiritRigMotion()
        motion.setState(.working)
        for _ in 0..<20 { _ = motion.advance(by: 1.0 / 60) }
        motion.setState(.completed)
        var celebrations = 0
        for _ in 0..<240 {
            let pose = motion.advance(by: 1.0 / 60)
            if pose.didCelebrate {
                #expect(!motion.isForging, "Finish the raised hammer before the proud reaction")
                celebrations += 1
            }
        }
        #expect(celebrations == 1)
    }

    @Test func pettingAccumulatesByTimeRatherThanPointerEventFrequency() {
        func petted(at fps: Int) -> SpiritRigPose {
            var motion = SpiritRigMotion()
            for _ in 0..<(fps / 3) {
                motion.setPointer(x: 8, y: 45, velocityX: 30)
                _ = motion.advance(by: 1.0 / Double(fps))
            }
            return motion.pose
        }
        let slow = petted(at: 30)
        let fast = petted(at: 120)
        #expect(abs(slow.eyeOpen - fast.eyeOpen) < 0.05)
        #expect(abs(slow.bodyOffsetY - fast.bodyOffsetY) < 0.1)
    }

    @Test func emberIntervalsVaryWhileKeepingStateDensityAndFrameRateIndependence() {
        func emissionFrames(state: SpiritState, fps: Int) -> [Int] {
            var motion = SpiritRigMotion()
            motion.setState(state)
            return (0..<(fps * 30)).filter { _ in motion.advance(by: 1.0 / Double(fps)).didEmitEmber }
        }
        for state: SpiritState in [.idle, .working] {
            let frames = emissionFrames(state: state, fps: 120)
            let gaps = zip(frames.dropFirst(), frames).map { $0 - $1 }
            #expect(Double(gaps.max()!) / Double(gaps.min()!) > 1.5)
            #expect(abs(frames.count - emissionFrames(state: state, fps: 30).count) <= 1)
            #expect(frames == emissionFrames(state: state, fps: 120))
            #expect(state == .working ? (85...102).contains(frames.count) : (14...19).contains(frames.count))
        }
    }

    @Test func depletedAndSleepingSpiritsEmitFewerEmbers() {
        func emissionCount(state: SpiritState, quota: Double) -> Int {
            var motion = SpiritRigMotion()
            motion.setRemainingQuota(quota)
            motion.setState(state)
            for _ in 0..<600 { _ = motion.advance(by: 1.0 / 60) }
            return (0..<1800).filter { _ in motion.advance(by: 1.0 / 60).didEmitEmber }.count
        }
        #expect(emissionCount(state: .working, quota: 0.05) < emissionCount(state: .working, quota: 1) * 4 / 5)
        #expect(emissionCount(state: .sleeping, quota: 1) < emissionCount(state: .idle, quota: 1) * 3 / 4)
    }

    @Test func blinkClosesBrieflyThenReopensMoreSlowly() {
        var motion = SpiritRigMotion()
        let frames = (0..<470).map { _ in motion.advance(by: 0.01).eyeOpen }
        let firstClosed = frames.firstIndex { $0 < 0.01 }!
        let lastClosed = frames.lastIndex { $0 < 0.01 }!
        let closingStart = frames.firstIndex { $0 < 0.99 }!
        let reopeningEnd = frames[(lastClosed + 1)...].firstIndex { $0 > 0.99 }!
        #expect(lastClosed - firstClosed >= 2)
        #expect(reopeningEnd - lastClosed > firstClosed - closingStart)
        #expect(reopeningEnd - closingStart < 30)
    }

    @Test func forgeArmAndSquashRemainContinuousAcrossMotionPhases() {
        for boundary in [0.45, 0.57] {
            var motion = SpiritRigMotion()
            motion.setState(.working)
            // Sample either side of the same boundary at sub-frame precision.
            for _ in 0..<(Int((boundary * 100).rounded()) - 1) { _ = motion.advance(by: 0.01) }
            let before = motion.advance(by: 0.0099)
            let after = motion.advance(by: 0.0002)
            #expect(abs(after.freeArmAngle - before.freeArmAngle) < 0.002)
            #expect(abs(after.bodyScaleY - before.bodyScaleY) < 0.002)
        }
    }

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
        let frames = (0..<123).map { _ in motion.advance(by: 1.0 / 60) }
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
                         p.freeArmAngle, p.impact, p.bodyScaleX, p.bodyAngle].allSatisfy { $0.isFinite })
                #expect((0...1).contains(p.impact) && (0...1).contains(p.eyeOpen))
            }
        }
    }

    @Test func existingFeedbackStatesRetainTheirOwnGestureWithoutSnapping() {
        for state: SpiritState in [.attention, .error, .greeting] {
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
        #expect(earlyIdle.contains { $0.playEmberOpacity > 0.5 })
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

    @Test func repeatedTapsChargeAndOrdinarySeparatedClicksDoNot() {
        var motion = SpiritRigMotion()
        for _ in 0..<2 {
            motion.beginPress()
            _ = motion.advance(by: 1.0 / 60)
            let chargedRelease = motion.endPress(registerTap: true)
            #expect(!chargedRelease)
        }
        motion.beginPress()
        _ = motion.advance(by: 1.0 / 60)
        let chargedRelease = motion.endPress(registerTap: true)
        #expect(chargedRelease)
        let charged = (0..<60).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(charged.contains { $0.charge > 0.25 })
        #expect(charged.filter(\.didTransform).count == 1)
        for _ in 0..<1200 { _ = motion.advance(by: 1.0 / 60) }
        #expect(motion.pose.charge < 0.01)
        for _ in 0..<3 {
            motion.beginPress()
            let chargedRelease = motion.endPress(registerTap: true)
            #expect(!chargedRelease)
            for _ in 0..<60 { _ = motion.advance(by: 1.0 / 60) }
        }
    }

    @Test func holdingChargesAndDragLeansWithoutInterruptingForge() {
        var motion = SpiritRigMotion()
        motion.setState(.working)
        motion.beginPress()
        let frames = (0..<180).map { _ in motion.advance(by: 1.0 / 60) }
        #expect(motion.pose.charge > 0.95)
        #expect(frames.filter(\.didTransform).count == 1)
        #expect(frames.filter(\.didStrike).count == 2)
        let chargedRelease = motion.endPress(registerTap: true)
        #expect(chargedRelease)
        for _ in 0..<60 {
            motion.setDragVelocity(x: 250, y: 120)
            _ = motion.advance(by: 1.0 / 60)
        }
        #expect(motion.pose.dragLean < -0.2)
        motion.setDragVelocity(x: 0, y: 0)
        for _ in 0..<180 { _ = motion.advance(by: 1.0 / 60) }
        #expect(abs(motion.pose.dragLean) < 0.01)
        let still = motion.advance(by: 1.0 / 60, reduceMotion: true)
        #expect(still.charge == 0 && !still.didTransform && still.dragLean == 0)
    }

}
