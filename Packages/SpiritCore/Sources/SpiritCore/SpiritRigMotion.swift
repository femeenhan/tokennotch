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
            pose.eyeOpen = state == .sleeping ? 0.12 : 1
            swingTime = nil
            gestureHead = 0
            gestureBody = 0
            gestureArm = 0
            return pose
        }
        let dt = delta.isFinite ? min(max(delta, 0), 1.0 / 20) : 0
        guard dt > 0 else {
            pose.didStrike = false
            return pose
        }
        elapsed += dt
        stateElapsed += dt
        if state == .working && swingTime == nil { swingTime = 0 }

        var next = SpiritRigPose()
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
        pose = next
        return next
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
