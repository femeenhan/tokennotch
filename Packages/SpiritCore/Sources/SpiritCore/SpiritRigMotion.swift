import Foundation

/// Positions use a 64-unit character space; angles are radians and scales are ratios.
public struct SpiritRigPose: Equatable, Sendable {
    public var hammerAngle: Double = 0
    public var bodyOffsetY: Double = 0
    public var bodyScaleY: Double = 1
    public var headAngle: Double = 0
    public var flameSway: Double = 0
    public var flameStretch: Double = 1
    public var eyeOpen: Double = 1
    public var gazeX: Double = 0
    public var freeArmAngle: Double = 0
    public var impact: Double = 0
    public var heat: Double = 0
    public var vitality: Double = 1
    public var restAmount: Double = 0
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
    private var recovery = 0.0
    private var pointerX: Double?
    private var pointerY: Double?
    private var gaze = 0.0
    private var wind = 0.0
    private var petting = 0.0
    private var surprise = 0.0
    private var surpriseCooldown = 0.0
    private var emberElapsed = 0.0
    private var idleElapsed = 0.0
    private var nextHabit = 12.0
    private var habitElapsed = 10.0
    private var habitIndex = 0
    private var habits = [1, 0, 2]

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
            if pointerX == nil && speed > 80 && abs(x!) < 25 && surpriseCooldown <= 0 {
                surprise = 1
                surpriseCooldown = 4
            }
            if velocityX.isFinite { wind = min(max(velocityX / 650, -0.3), 0.3) }
            if y! > 32 && y! < 62 && abs(x!) < 22 && speed > 8 && speed < 170 {
                petting = min(1, petting + 0.08)
            }
            pointerX = x
            pointerY = y
        } else {
            pointerX = nil
            pointerY = nil
        }
    }

    private static let strikeTime = 0.57
    private static let cycleDuration = 1.5

    public init() {}

    public mutating func setState(_ state: SpiritState) {
        guard state != self.state else { return }
        self.state = state
        stateElapsed = 0
        // A requested stop does not interrupt a raised hammer: finish and recover first.
        if state == .working && swingTime == nil { swingTime = 0 }
    }

    @discardableResult
    public mutating func advance(by delta: Double, reduceMotion: Bool = false) -> SpiritRigPose {
        if reduceMotion {
            pose = SpiritRigPose()
            pose.restAmount = state == .sleeping || (state == .idle && remainingQuota == 0) ? 1 : 0
            pose.eyeOpen = pose.restAmount == 1 ? 0.12 : 1
            pose.hammerAngle = pose.restAmount * 0.95
            pose.headAngle = pose.restAmount * 0.035
            pose.vitality = quotaVitality
            pose.heat = state == .working ? 0.65 : 0
            pose.emberGlow = state == .sleeping ? 0.4 : 0.65 + 0.35 * quotaVitality
            swingTime = nil
            gestureHead = 0
            gestureBody = 0
            gestureArm = 0
            return pose
        }
        let dt = delta.isFinite ? min(max(delta, 0), 1.0 / 20) : 0
        guard dt > 0 else {
            pose.didStrike = false
            pose.didCelebrate = false
            pose.didEmitEmber = false
            return pose
        }
        elapsed += dt
        stateElapsed += dt
        if state == .working && swingTime == nil { swingTime = 0 }

        let targetVitality = quotaVitality
        vitality += (targetVitality - vitality) * (1 - exp(-dt * 2))
        heat += ((state == .working ? 1.0 : 0.0) - heat) * (1 - exp(-dt * (state == .working ? 2 : 0.12)))
        recovery = max(0, recovery - dt)
        surprise = max(0, surprise - dt * 2.5)
        surpriseCooldown = max(0, surpriseCooldown - dt)
        wind *= exp(-dt * 5)
        petting *= exp(-dt * 0.7)
        idleElapsed = state == .idle ? idleElapsed + dt : 0
        habitElapsed += dt
        if state == .idle && idleElapsed >= nextHabit {
            habitElapsed = 0
            if habits.isEmpty { habits = [0, 1, 2].shuffled() }
            habitIndex = habits.removeFirst()
            nextHabit = idleElapsed + 13 + Double.random(in: 0...8)
        }
        if state != .idle { nextHabit = 12 }
        var next = SpiritRigPose()
        next.vitality = vitality
        next.heat = heat
        next.emberGlow = (0.55 + 0.45 * vitality) * (state == .sleeping ? 0.5 : 1)
        next.didCelebrate = state == .completed && stateElapsed <= dt
        emberElapsed += dt
        if emberElapsed > (state == .working || petting > 0.3 ? 0.32 : 1.8) {
            next.didEmitEmber = true
            emberElapsed = 0
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
            next.eyeOpen = abs(blinkPhase - 3.72) / 0.12
        }
        if state == .sleeping { next.eyeOpen = 0.12 }

        if let previous = swingTime {
            let time = previous + dt
            next.didStrike = previous < Self.strikeTime && time >= Self.strikeTime
            next.hammerAngle = hammerAngle(at: time)
            if time < 0.45 {
                let lift = smooth(time / 0.45)
                next.bodyOffsetY += 0.5 * lift
                next.headAngle -= 0.045 * lift
                next.freeArmAngle -= 0.12 * lift
            } else if time < Self.strikeTime {
                let drop = smooth((time - 0.45) / 0.12)
                next.bodyOffsetY += 0.5 - 2 * drop
                next.headAngle += -0.045 + 0.09 * drop
            } else {
                let sinceStrike = time - Self.strikeTime
                let rebound = exp(-sinceStrike * 9)
                next.impact = next.didStrike ? 1 : exp(-sinceStrike * 18)
                next.bodyOffsetY -= 1.5 * rebound * cos(sinceStrike * 15)
                next.bodyScaleY -= 0.09 * rebound
                next.headAngle += 0.045 * rebound
                next.flameSway += 0.13 * rebound * sin(sinceStrike * 15)
                next.flameStretch += 0.12 * rebound * sin(sinceStrike * 12)
                next.freeArmAngle += 0.14 * rebound
            }
            if time >= Self.cycleDuration {
                swingTime = state == .working ? time - Self.cycleDuration : nil
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
            targetArm = -0.25 + 0.05 * sin(stateElapsed * 5)
        case .completed:
            targetBody = stateElapsed < 0.65 ? 2.6 * sin(.pi * stateElapsed / 0.65) : 0
            targetArm = stateElapsed < 0.8 ? -0.4 * sin(.pi * stateElapsed / 0.8) : 0
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
        let resting = state == .sleeping || (state == .idle && (idleElapsed > 55 || remainingQuota == 0))
        // Rest is a composed pose. Never stack head/body squash with quota loss.
        let restTarget = resting && swingTime == nil ? 1.0 : 0.0
        restAmount += (restTarget - restAmount) * (1 - exp(-dt * 4))
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
            next.eyeOpen = 0.12
            next.emberGlow *= 0.7 + 0.08 * sin(elapsed * 1.2)
        }
        let gazeTarget = pointerX.map { min(max($0 / 14, -1.8), 1.8) } ?? (0.4 * sin(elapsed * 0.65))
        gaze += (gazeTarget - gaze) * (1 - exp(-dt * 7))
        next.gazeX = gaze
        next.gazeY = pointerY.map { min(max(($0 - 28) / 30, -0.6), 0.6) } ?? 0
        if state != .working {
            next.headAngle += gaze * 0.025
            next.bodyOffsetY += petting * 0.35
            next.eyeOpen *= 1 - petting * 0.65
            if recovery > 0 {
                let stretch = sin(.pi * (1 - recovery / 2.4))
                next.bodyOffsetY += stretch * 1.4
                next.flameStretch += stretch * 0.2
                next.freeArmAngle -= stretch * 0.4
            }
            if state == .idle && habitElapsed < 2.4 && !resting {
                let gesture = sin(.pi * habitElapsed / 2.4)
                switch habitIndex {
                case 0: // Comb the flame.
                    next.freeArmAngle -= gesture * 1.1
                    next.flameSway += gesture * 0.12
                case 1: // Catch and release a floating ember.
                    next.freeArmAngle -= gesture * 0.75
                    next.heldEmber = gesture
                default: // A little fiery yawn / tired, contented sigh.
                    next.mouthOpen = 1 + gesture * 1.8
                    next.eyeOpen *= 1 - gesture * 0.75
                    next.flameStretch += gesture * 0.18
                    next.headAngle += gesture * 0.1
                }
            }
        }
        if state == .attention { next.heldEmber = 0.8 + 0.2 * sin(stateElapsed * 3) }
        next.emberGlow = min(max(next.emberGlow + next.impact * 0.3 + petting * 0.15, 0), 1)
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
