import Foundation

public enum SpiritExpression: Equatable, Sendable {
    case neutral, focused, content, surprised, proud, tired, sleeping, curious, requesting, worried, yawning
}

/// Positions use a 64-unit character space; angles are radians and scales are ratios.
public struct SpiritRigPose: Equatable, Sendable {
    /// Zero holds the tool ready; one rests its head on the ground.
    public var hammerRest: Double = 0
    public var hammerAngle: Double = 0
    public var bodyOffsetY: Double = 0
    public var bodyScaleY: Double = 1
    public var bodyScaleX: Double = 1
    public var bodyAngle: Double = 0
    public var expression: SpiritExpression = .neutral
    public var headAngle: Double = 0
    public var flameSway: Double = 0
    public var flameStretch: Double = 1
    public var eyeReopen: Double = 1
    public var workSurface: Double = 0
    public var strikeStrength: Double = 0
    public var playEmberOpacity: Double = 0
    public var playEmberX: Double = 0
    public var playEmberY: Double = 0
    public var didRequestHammerTrick = false
    public var eyeOpen: Double = 1
    public var gazeX: Double = 0
    public var freeArmAngle: Double = 0
    public var impact: Double = 0
    public var heat: Double = 0
    public var vitality: Double = 1
    public var restAmount: Double = 0
    public var charge: Double = 0
    public var dragLean: Double = 0
    public var didTransform: Bool = false
    public var emberGlow: Double = 1
    public var heldEmber: Double = 0
    public var didCelebrate: Bool = false
    public var didEmitEmber: Bool = false
    public var mouthOpen: Double = 1
    public var gazeY: Double = 0
    public var didStrike: Bool = false

    public init() {}
}

/// Continuous part-level animation, independent from rendering and live session events.
public struct SpiritRigMotion: Sendable {
    public private(set) var pose = SpiritRigPose()
    /// Includes the final recovery after work ends, while the hammer is still occupied.
    public var isForging: Bool { swingTime != nil }
    public var isPerformingHabit: Bool { emberTime != nil }
    public var canPlayIdleAction: Bool {
        state == .idle && swingTime == nil && completionTime == nil && !idleActionActive
            && !dragging && liftAmount < 0.05 && petting < 0.15 && !stroking
            && pressElapsed == nil && charge < 0.1 && emberTime == nil && restAmount < 0.2 && restElapsed == 0 && remainingQuota != 0
    }
    private var typingActive = false
    public private(set) var typingAmount = 0.0

    public mutating func setTypingActive(_ active: Bool) {
        typingActive = active
        if active { registerActivity() }
    }

    private var hammerRestProgress = 1.0
    private var idleActionActive = false
    private var completionTime: Double?
    private var dragging = false
    private var liftAmount = 0.0
    private var releaseTime = 2.0
    private var releaseStrength = 0.0
    private var stroking = false

    public mutating func setIdleActionActive(_ active: Bool) {
        idleActionActive = active
        if active { emberTime = nil }
    }

    public mutating func setDragging(_ active: Bool) {
        guard active != dragging else { return }
        dragging = active
        if active { registerActivity() }
        if active {
            completionTime = nil
            pressElapsed = nil
            petting = 0
            stroking = false
            emberTime = nil
            idleElapsed = 0
        } else {
            releaseTime = 0
            releaseStrength = liftAmount
            dragX = 0
            dragY = 0
        }
    }
    private var state: SpiritState = .idle
    private var elapsed = 0.0
    private var stateElapsed = 0.0
    private var gestureHead = 0.0
    private var gestureBody = 0.0
    private var gestureArm = 0.0
    private var swingTime: Double?
    private var remainingQuota: Double?
    private var vitality = 1.0
    private var heat = 0.0
    private var restAmount = 0.0
    private var pressElapsed: Double?
    private var tapEnergy = 0.0
    private var charge = 0.0
    private var interactionTime = 0.0
    private var lastTapTime = -10.0
    private var tapCount = 0
    private var dragX = 0.0
    private var dragY = 0.0
    private var dragVelocityAge = 0.0
    private var dragLean = 0.0
    private var transformed = false

    public mutating func beginPress() {
        pressElapsed = 0
        registerActivity()
        completionTime = nil
        emberTime = nil
    }

    /// Returns true when release belongs to charging, rather than an ordinary click.
    @discardableResult
    public mutating func endPress(registerTap: Bool) -> Bool {
        let held = (pressElapsed ?? 0) >= 0.45
        pressElapsed = nil
        if registerTap && !held {
            tapCount = interactionTime - lastTapTime < 0.75 ? tapCount + 1 : 1
            lastTapTime = interactionTime
            if tapCount >= 3 { tapEnergy = min(1, tapEnergy + 0.55) }
        }
        return held || (registerTap && tapCount >= 3)
    }

    /// Screen velocity normalized by the renderer to the 64-unit character space.
    public mutating func setDragVelocity(x: Double, y: Double) {
        dragVelocityAge = 0
        dragX = x.isFinite ? min(max(x, -300), 300) : 0
        dragY = y.isFinite ? min(max(y, -300), 300) : 0
    }
    private var recovery = 0.0
    private var pointerX: Double?
    private var pointerY: Double?
    private var gaze = 0.0
    private var wind = 0.0
    private var petting = 0.0
    private var surprise = 0.0
    private var emberProgress = 0.0
    private var emberSpacing = 0.91
    private var emberSequence = 0.37
    private var idleElapsed = 0.0
    private var nextIdleAction = 25.0
    private var automaticIdleActions = true
    private var emberTime: Double?
    private var nextActionIsEmber = true
    private var pointerDwell = 0.0
    private var gazeCooldown = 0.0
    private var gazeReaction = false
    private var pettingElapsed = 0.0
    private var pettingRelease = 1.0
    private var workPetting = 0.0
    private var workPettingPending = false
    private var strikeIndex = 0
    private var restElapsed = 0.0
    private var wakeElapsed = 0.5
    private var wakeRest = 0.0

    public mutating func setAutomaticIdleActionsEnabled(_ enabled: Bool) { automaticIdleActions = enabled }

    @discardableResult
    public mutating func playEmberPlay() -> Bool {
        guard canPlayIdleAction else { return false }
        emberTime = 0
        return true
    }

    public mutating func cancelInteractions() {
        dragging = false
        liftAmount = 0
        releaseTime = 2
        releaseStrength = 0
        pressElapsed = nil
        stroking = false
        petting = 0
        pettingElapsed = 0
        pettingRelease = 1
        dragX = 0
        dragY = 0
        dragLean = 0
        completionTime = nil
        emberTime = nil
        idleActionActive = false
        pointerX = nil
        pointerY = nil
        pointerDwell = 0
        gazeReaction = false
        tapEnergy = 0
        charge = 0
        workPettingPending = false
        let hammerRest = pose.hammerRest
        let hammer = pose.hammerAngle
        pose = SpiritRigPose()
        pose.hammerRest = hammerRest
        pose.vitality = vitality
        pose.heat = heat
        pose.restAmount = restAmount
        pose.hammerAngle = isForging ? hammer : restAmount * 0.95
        pose.workSurface = isForging ? 1 : 0
        pose.expression = state == .working ? .focused : state == .attention ? .requesting
            : state == .error ? .worried : state == .sleeping ? .sleeping : .neutral
    }

    private mutating func registerActivity() {
        idleElapsed = 0
        nextIdleAction = max(nextIdleAction, elapsed + 25)
        if restAmount > 0 && wakeElapsed >= 0.5 {
            wakeRest = restAmount
            wakeElapsed = 0
        }
    }

    /// A missing or invalid observation must not imply exhaustion.
    public mutating func setRemainingQuota(_ value: Double?) {
        let next = value.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil }
        if let old = remainingQuota, let next, next - old > 0.15 { recovery = 2.4 }
        remainingQuota = next
    }

    /// Coordinates and velocities are in the character's 64-unit space.
    public mutating func setPointer(x: Double?, y: Double?, velocityX: Double = 0, velocityY: Double = 0) {
        let nearby = x?.isFinite == true && y?.isFinite == true
            && abs(x!) < 75 && abs(y! - 28) < 65
        if nearby {
            let speed = hypot(velocityX, velocityY)
            if pointerX == nil {
                pointerDwell = 0
                gazeReaction = gazeCooldown <= 0
                registerActivity()
            }
            if velocityX.isFinite { wind = min(max(velocityX / 650, -0.3), 0.3) }
            stroking = !dragging && y! > 32 && y! < 62 && abs(x!) < 22 && speed > 8 && speed < 170
            if speed > 8 { registerActivity() }
            pointerX = x
            pointerY = y
        } else {
            stroking = false
            pointerDwell = 0
            gazeReaction = false
            pointerX = nil
            pointerY = nil
        }
    }

    private static let strikeTime = 0.57
    private static let cycleDuration = 1.5

    public init() { pose.hammerRest = 1 }

    public mutating func setState(_ state: SpiritState) {
        guard state != self.state else { return }
        let wasSleeping = self.state == .sleeping
        self.state = state
        stateElapsed = 0
        if state == .completed {
            completionTime = !wasSleeping && !dragging && !stroking && petting < 0.01 && pressElapsed == nil && restAmount < 0.2 && quotaVitality >= 0.6 ? 0 : nil
        }
        else if state != .idle { completionTime = nil }
        if state != .idle {
            emberTime = nil
            petting = 0
            pettingElapsed = 0
            pettingRelease = 1
            workPetting = 0
            workPettingPending = false
        }
        if state == .working {
            registerActivity()
            strikeIndex = 0
        }
        // A requested stop does not interrupt a raised hammer: finish and recover first.
        if state == .working && swingTime == nil { swingTime = -0.55 }
    }

    @discardableResult
    public mutating func advance(by delta: Double, reduceMotion: Bool = false) -> SpiritRigPose {
        if reduceMotion {
            hammerRestProgress = (state == .idle || state == .sleeping)
                && !idleActionActive && !dragging && pressElapsed == nil && !stroking
                && petting < 0.01 && charge < 0.1 && completionTime == nil ? 1 : 0
            typingAmount = 0
            pose = SpiritRigPose()
            pose.hammerRest = hammerRestProgress
            pose.restAmount = state == .sleeping || (state == .idle && remainingQuota == 0) ? 1 : 0
            pose.eyeOpen = pose.restAmount == 1 ? 0.12 : 1
            pose.hammerAngle = pose.restAmount * 0.95
            pose.headAngle = pose.restAmount * 0.035
            pose.vitality = quotaVitality
            pose.expression = pose.restAmount == 1 ? .sleeping
                : state == .completed ? .proud : state == .working ? .focused
                : state == .attention ? .requesting : state == .error ? .worried
                : quotaVitality < 0.6 ? .tired : .neutral
            pose.heat = state == .working ? 0.65 : 0
            pose.emberGlow = state == .sleeping ? 0.4 : 0.65 + 0.35 * quotaVitality
            pose.workSurface = state == .working ? 1 : 0
            emberTime = nil
            swingTime = nil
            gestureHead = 0
            gestureBody = 0
            gestureArm = 0
            completionTime = nil
            petting = 0
            liftAmount = 0
            releaseTime = 2
            releaseStrength = 0
            return pose
        }
        let dt = delta.isFinite ? min(max(delta, 0), 1.0 / 20) : 0
        guard dt > 0 else {
            pose.didStrike = false
            pose.didCelebrate = false
            pose.didEmitEmber = false
            pose.didTransform = false
            pose.didRequestHammerTrick = false
            return pose
        }
        gazeCooldown = max(0, gazeCooldown - dt)
        if pointerX != nil {
            let old = pointerDwell
            pointerDwell += dt
            if old < 0.18 && pointerDwell >= 0.18 && gazeReaction { gazeCooldown = 4 }
        }
        interactionTime += dt
        releaseTime += dt
        liftAmount += ((dragging ? 1.0 : 0.0) - liftAmount) * (1 - exp(-dt * (dragging ? 9 : 14)))
        if let held = pressElapsed { pressElapsed = held + dt }
        tapEnergy = max(0, tapEnergy - dt * 0.12)
        let heldCharge = pressElapsed.map { min(1, max(0, ($0 - 0.45) / 1.35)) } ?? 0
        let targetCharge = max(tapEnergy, heldCharge)
        charge += (targetCharge - charge) * (1 - exp(-dt * (targetCharge > charge ? 7 : 0.65)))
        dragVelocityAge += dt
        if dragVelocityAge > 0.08 {
            dragX *= exp(-dt * 10)
            dragY *= exp(-dt * 10)
        }
        dragLean += (min(max(-dragX / 700, -0.3), 0.3) - dragLean) * (1 - exp(-dt * 8))
        elapsed += dt
        stateElapsed += dt
        if state == .working && swingTime == nil { swingTime = -0.55 }

        let targetVitality = quotaVitality
        vitality += (targetVitality - vitality) * (1 - exp(-dt * 2))
        heat += ((state == .working ? 1.0 : 0.0) - heat) * (1 - exp(-dt * (state == .working ? 2 : 0.12)))
        recovery = max(0, recovery - dt)
        surprise = max(0, surprise - dt * 2.5)
        wind *= exp(-dt * 5)
        let receivesPetting = stroking && !dragging && swingTime == nil
            && !idleActionActive && (state == .idle || state == .sleeping)
        if receivesPetting {
            completionTime = nil
            emberTime = nil
            pettingElapsed += dt
            pettingRelease = 0
            petting = smooth((pettingElapsed - 0.25) / 0.45)
        } else {
            pettingRelease += dt
            if pettingRelease > 0.12 { pettingElapsed = 0 }
            if pettingRelease > 0.35 { petting *= exp(-dt * 7) }
            if pettingRelease >= 0.9 { petting = 0 }
        }
        if state == .working && stroking { workPettingPending = true }
        workPetting = max(0, workPetting - dt)
        idleElapsed = state == .idle ? idleElapsed + dt : 0
        let hasInteraction = dragging || liftAmount > 0.05 || petting > 0.01 || charge > 0.1 || pressElapsed != nil
        if hasInteraction { emberTime = nil; completionTime = nil }
        var next = SpiritRigPose()
        if automaticIdleActions && !typingActive && elapsed >= nextIdleAction && canPlayIdleAction && pointerX == nil && idleElapsed < 55 {
            if nextActionIsEmber { emberTime = 0 }
            else { next.didRequestHammerTrick = true }
            nextActionIsEmber.toggle()
            nextIdleAction = elapsed + 25 + 20 * emberSequence
        }
        next.vitality = vitality
        next.charge = charge
        next.dragLean = dragLean
        next.didTransform = charge > 0.25 && !transformed
        if charge > 0.25 { transformed = true }
        if charge < 0.08 { transformed = false }
        next.heat = heat
        next.emberGlow = (0.55 + 0.45 * vitality) * (state == .sleeping ? 0.5 : 1)
        let emberInterval = (state == .working || petting > 0.3 ? 0.32 : 1.8)
            * (1 + 0.6 * (1 - vitality) + 0.8 * restAmount)
        // Accumulate in interval units so waking or starting work responds immediately.
        emberProgress += dt / emberInterval
        if emberProgress >= emberSpacing {
            next.didEmitEmber = true
            emberProgress -= emberSpacing
            // An irrational step varies each emission without randomizing every frame.
            emberSequence = (emberSequence + 0.618033988749895).truncatingRemainder(dividingBy: 1)
            emberSpacing = 0.65 + 0.7 * emberSequence
        }
        let breath = sin(elapsed * 2.1)
        next.bodyOffsetY = 0.3 * breath
        next.bodyScaleY = 1 + 0.018 * breath
        next.headAngle = 0.016 * sin(elapsed * 1.3)
        // Independent frequencies keep the silhouette from moving like one rigid card.
        next.flameSway = 0.065 * sin(elapsed * 3.1) + 0.024 * sin(elapsed * 7.7)
        next.flameStretch = 1 + 0.035 * sin(elapsed * 4.3) + 0.014 * sin(elapsed * 9.1)
        next.freeArmAngle = 0.025 * sin(elapsed * 2.1 - 0.7)
        next.gazeX = 0.4 * sin(elapsed * 0.65)
        let blinkPhase = elapsed.truncatingRemainder(dividingBy: 4.7)
        if blinkPhase > 3.6 && blinkPhase < 3.84 {
            let blinkTime = blinkPhase - 3.6
            // Close briskly, hold for two frames, then let the lids open softly.
            if blinkTime < 0.07 {
                next.eyeOpen = 1 - smooth(blinkTime / 0.07)
            } else if blinkTime < 0.105 {
                next.eyeOpen = 0
            } else {
                next.eyeOpen = smooth((blinkTime - 0.105) / 0.135)
            }
        }
        if state == .sleeping { next.eyeOpen = 0.12 }

        if let previous = swingTime {
            let time = previous + dt / (1 + 0.45 * (1 - quotaVitality))
            next.didStrike = previous < Self.strikeTime && time >= Self.strikeTime
            next.strikeStrength = strikeIndex % 3 == 2 ? 1 : 0.55
            let force = strikeIndex % 3 == 2 ? 1.25 : 0.85
            let baseHammer = hammerAngle(at: max(0, time))
            // Keep the contact angle fixed; weight changes windup and the body's recoil.
            next.hammerAngle = baseHammer < 0 ? baseHammer * force : baseHammer
            next.workSurface = 1
            next.gazeX = -1.3
            next.gazeY = -0.6
            if time >= 0.75 && workPettingPending {
                workPetting = 0.35
                workPettingPending = false
            }
            if time < 0.45 {
                let lift = smooth(time / 0.45)
                next.bodyOffsetY += 0.5 * lift
                next.headAngle -= 0.045 * lift
                next.freeArmAngle -= 0.12 * lift
            } else if time < Self.strikeTime {
                let drop = smooth((time - 0.45) / 0.12)
                next.bodyOffsetY += 0.5 - 2 * drop
                next.headAngle += -0.045 + 0.09 * drop
                // Carry the counterweight arm and compression into the impact pose.
                next.freeArmAngle += -0.12 + 0.26 * drop
                next.bodyScaleY -= 0.09 * drop * drop * force
            } else {
                let sinceStrike = time - Self.strikeTime
                let rebound = exp(-sinceStrike * 9)
                next.impact = next.didStrike ? 1 : exp(-sinceStrike * 18)
                next.bodyOffsetY -= 1.5 * rebound * cos(sinceStrike * 15) * force
                next.bodyScaleY -= 0.09 * rebound * force
                next.headAngle += 0.045 * rebound
                next.flameSway += 0.13 * rebound * sin(sinceStrike * 15) * force
                next.flameStretch += 0.12 * rebound * sin(sinceStrike * 12)
                next.freeArmAngle += 0.14 * rebound
            }
            let duration = Self.cycleDuration + (strikeIndex % 3 == 1 ? 0.5 : 0)
            if time >= duration {
                strikeIndex += 1
                swingTime = state == .working ? time - duration : nil
            } else {
                swingTime = time
            }
        }
        // Preserve existing status gestures as additive offsets, easing both in and out.
        // These never replace the forge timeline, so a raised hammer still recovers safely.
        var targetHead = 0.0
        var targetBody = 0.0
        var targetArm = 0.0
        switch state {
        case .attention:
            targetHead = -0.12
            targetBody = 0.6
            targetArm = 1.1 * smooth(stateElapsed / 1)
        case .completed:
            break // The completion phrase starts only after the last strike recovers.
        case .error:
            targetHead = 0.2 * sin(stateElapsed * 22) * exp(-stateElapsed * 1.5)
            targetArm = 0.2
        case .greeting:
            targetHead = 0.12 * sin(stateElapsed * 9) * exp(-stateElapsed)
            targetArm = -0.4 * sin(min(stateElapsed / 0.9, 1) * .pi)
        case .idle, .working, .sleeping:
            break
        }
        let blend = 1 - exp(-dt * 10)
        gestureHead += (targetHead - gestureHead) * blend
        gestureBody += (targetBody - gestureBody) * blend
        gestureArm += (targetArm - gestureArm) * blend
        next.headAngle += gestureHead
        next.bodyOffsetY += gestureBody
        next.freeArmAngle += gestureArm
        if state == .working && stateElapsed < 0.45 {
            let ignition = sin(.pi * stateElapsed / 0.45)
            next.bodyScaleY -= ignition * 0.025
            next.flameStretch += ignition * 0.15
        }
        let resting = (state == .sleeping || (state == .idle && (idleElapsed > 55 || remainingQuota == 0)))
            && !hasInteraction && completionTime == nil
        // Rest is a composed pose. Never stack head/body squash with quota loss.
        let restTarget = resting && swingTime == nil && charge < 0.1 && dragX == 0 && dragY == 0
        if restTarget {
            restElapsed += dt
            restAmount = smooth((restElapsed - 1.2) / 1.8)
            wakeElapsed = 0.5
        } else {
            restElapsed = 0
            if restAmount > 0 && wakeElapsed >= 0.5 { wakeRest = restAmount; wakeElapsed = 0 }
            wakeElapsed = min(0.5, wakeElapsed + dt)
            restAmount = wakeRest * (1 - smooth(wakeElapsed / 0.5))
        }
        next.restAmount = restAmount
        next.flameStretch += 0.12 * heat - 0.07 * (1 - vitality) - 0.035 * restAmount
        next.flameSway *= 0.65 + 0.55 * vitality + 0.2 * heat
        next.flameSway += wind + surprise * 0.09
        next.flameStretch += surprise * 0.25
        next.bodyOffsetY -= (1 - vitality) * 0.35
        next.headAngle += (1 - vitality) * 0.025 + restAmount * 0.035
        next.freeArmAngle += restAmount * 0.22
        if swingTime == nil { next.hammerAngle += restAmount * 0.95 }
        next.flameSway *= 1 - restAmount * 0.65
        if state == .idle { next.eyeOpen *= 0.8 + 0.2 * vitality }
        if resting {
            next.eyeOpen = 1 - 0.88 * smooth(restElapsed / 3)
            next.emberGlow *= 0.7 + 0.08 * sin(elapsed * 1.2)
        }
        let gazeTarget = pointerX.map { min(max($0 / 14, -1.8), 1.8) } ?? 0
        gaze += (gazeTarget - gaze) * (1 - exp(-dt * 7))
        next.gazeX = gaze
        next.gazeY = pointerY.map { min(max(($0 - 28) / 30, -0.6), 0.6) } ?? 0
        if state != .working {
            next.headAngle += gazeReaction ? gaze * 0.06 * smooth((pointerDwell - 0.18) / 0.27) : 0
            if recovery > 0 {
                let stretch = sin(.pi * (1 - recovery / 2.4))
                next.bodyOffsetY += stretch * 1.4
                next.flameStretch += stretch * 0.2
                next.freeArmAngle -= stretch * 0.4
            }
        }
        if state == .attention { next.heldEmber = smooth(stateElapsed / 1) }
        next.emberGlow = min(max(next.emberGlow + next.impact * 0.3 + petting * 0.15, 0), 1)
        next.flameSway += dragLean
        next.flameStretch += 0.28 * charge + min(abs(dragY) / 1400, 0.12)
        next.headAngle += dragLean * 0.15
        if charge > 0.1 {
            next.eyeOpen = max(next.eyeOpen, 0.8)
            next.bodyOffsetY += charge * 0.55
            next.freeArmAngle += charge * 0.3
        }
        next.expression = resting ? (restElapsed < 1.5 ? .yawning : restElapsed < 3 ? .tired : .sleeping) : vitality < 0.6 ? .tired
            : swingTime != nil ? .focused : surprise > 0.2 ? .surprised : .neutral

        if resting && restElapsed < 1.5 { next.mouthOpen = 1 + sin(.pi * min(restElapsed / 1.5, 1)) * 1.6 }
        if !resting && wakeElapsed < 0.5 { next.eyeOpen = 1 }
        if state == .completed && completionTime == nil && quotaVitality < 0.6 { next.expression = .proud }
        if state == .attention { next.expression = .requesting }
        if state == .error { next.expression = stateElapsed < 0.2 ? .surprised : .worried }
        if state == .idle && pointerX != nil && !resting { next.expression = .curious }
        if state == .working || swingTime != nil {
            next.gazeX = pointerX != nil && pointerDwell < 0.45 ? gaze * 0.5 : -1.3
            next.gazeY = -0.6
            if workPetting > 0 { next.expression = .content }
        }
        if let previous = emberTime {
            let t = previous + dt
            emberTime = t < 3.2 ? t : nil
            next.playEmberOpacity = smooth(t / 0.15) * (1 - smooth((t - 2.9) / 0.3))
            next.playEmberX = 20 - 3.2 * smooth((t - 1.55) / 0.6)
            next.playEmberY = t < 1.55 ? 20 + 10 * smooth(t / 1.15)
                : t < 2.65 ? 30 - 16 * smooth((t - 1.55) / 0.6)
                : 14 + 15 * smooth((t - 2.65) / 0.55)
            next.freeArmAngle = 1.4 * smooth((t - 0.45) / 0.7) - 0.3 * smooth((t - 1.55) / 0.6)
            next.freeArmAngle *= 1 - smooth((t - 2.65) / 0.55)
            next.headAngle += 0.09 * smooth((t - 0.45) / 0.35)
            next.gazeX = t > 2.35 && t < 2.65 ? 0 : 1.2
            next.gazeY = (next.playEmberY - 22) / 18
            next.expression = t < 2.15 ? .curious : .proud
        }
        // One authored phrase owns the face and silhouette; background breath remains small.
        if let time = completionTime, swingTime == nil && !hasInteraction && !idleActionActive {
            let t = time + dt
            completionTime = t < 3 ? t : nil
            let fade = 1 - smooth((t - 2.3) / 0.7)
            let anticipation = smooth((t - 0.65) / 0.2) * (1 - smooth((t - 0.85) / 0.1))
            let hop = t >= 0.85 && t < 1.2 ? sin(.pi * (t - 0.85) / 0.35) : 0
            let landing = t >= 1.2 ? sin(min((t - 1.2) / 0.25, 1) * .pi) : 0
            next.bodyOffsetY += -0.8 * anticipation + 3.2 * hop - 0.65 * landing
            next.bodyScaleY *= 1 - 0.10 * anticipation + 0.055 * hop - 0.065 * landing
            next.headAngle += -0.07 * anticipation + 0.075 * smooth((t - 0.65) / 0.4) * fade
            next.freeArmAngle += (0.22 * anticipation + 0.85 * smooth((t - 0.85) / 0.35)) * fade
            next.flameStretch += 0.12 * hop
            next.gazeX *= 1 - fade
            next.gazeY = t < 0.35 ? -0.55 : 0
            next.workSurface = 1 - smooth((t - 0.35) / 0.3)
            next.hammerAngle += 0.16 * fade
            next.expression = t < 0.35 ? .focused : t < 3 ? .proud : .neutral
            next.didCelebrate = time < 0.85 && t >= 0.85
        }
        if petting > 0.01 && !dragging && swingTime == nil {
            next.bodyScaleY *= 1 - 0.085 * petting
            next.bodyOffsetY += 0.4 * petting
            next.headAngle += min(max((pointerX ?? 0) / 80, -0.13), 0.13) * petting
            next.freeArmAngle += 0.35 * petting
            next.hammerAngle += 0.16 * petting
            next.eyeOpen *= 1 - 0.72 * petting
            next.flameSway *= 1 - 0.55 * petting
            next.flameStretch -= 0.07 * petting
            if petting > 0.01 { next.expression = .content }
            next.eyeReopen = smooth((pettingRelease - 0.35) / 0.55)
        }
        let settle = releaseTime < 1.2 ? -0.12 * releaseStrength * sin(releaseTime * 16) * exp(-releaseTime * 5) : 0
        next.bodyScaleY *= 1 + 0.17 * liftAmount + settle
        next.bodyOffsetY -= 3.5 * liftAmount
        next.bodyAngle = dragLean * 0.38
        next.headAngle -= dragLean * 0.25
        next.freeArmAngle += 0.4 * liftAmount
        next.flameStretch += 0.10 * liftAmount
        if dragging || liftAmount > 0.2 {
            next.expression = .surprised
            next.eyeOpen = 1
            next.gazeY = 0.6
        }
        if !dragging && releaseTime >= 0.65 && releaseTime < 1.1 {
            let regrip = sin(.pi * (releaseTime - 0.65) / 0.45) * releaseStrength
            next.hammerAngle += 0.12 * regrip
            next.gazeX *= 1 - regrip
        }
        // A restrained response to a typing burst, subordinate to all direct interactions.
        let typingAllowed = canPlayIdleAction
        let typingTarget = typingActive && typingAllowed ? 1.0 : 0.0
        typingAmount += (typingTarget - typingAmount) * min(1, dt / 0.25)
        if !typingAllowed { typingAmount = 0 }
        if typingAmount > 0.001 {
            let nod = (1 - cos(elapsed * 4.2)) * 0.5
            next.headAngle += typingAmount * (0.025 + 0.035 * nod)
            next.bodyOffsetY -= typingAmount * 0.28 * nod
            next.gazeY -= typingAmount * 0.45
            next.flameSway += typingAmount * 0.035 * sin(elapsed * 4.2 - 0.5)
            next.flameStretch += typingAmount * 0.025 * nod
            if typingAmount > 0.35 { next.expression = .focused }
            next.didRequestHammerTrick = false
        }
        // Finish the final forge recovery before setting down the tool. Typing is
        // intentionally not an interruption: the small nod keeps the hammer grounded.
        let groundHammer = (state == .idle || state == .sleeping) && swingTime == nil
            && !hasInteraction && !stroking && !idleActionActive && completionTime == nil
        hammerRestProgress = groundHammer
            ? min(1, hammerRestProgress + dt / 0.4)
            : max(0, hammerRestProgress - dt / 0.4)
        next.hammerRest = smooth(hammerRestProgress)
        // Preserve approximate area through compression and stretch.
        next.bodyScaleX = 1 / sqrt(next.bodyScaleY)
        pose = next
        return next
    }

    private var quotaVitality: Double {
        guard let remainingQuota else { return 1 }
        if remainingQuota == 0 { return 0.12 }
        return 0.25 + 0.75 * min(remainingQuota / 0.5, 1)
    }

    private func hammerAngle(at time: Double) -> Double {
        if time < 0.45 { return -0.7 * smooth(time / 0.45) }
        if time < 0.57 { return -0.7 + 2 * smooth((time - 0.45) / 0.12) }
        if time < 0.65 { return 1.3 - 0.15 * smooth((time - 0.57) / 0.08) }
        if time < 1.15 { return 1.15 * (1 - smooth((time - 0.65) / 0.5)) }
        return 0
    }

    private func smooth(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
