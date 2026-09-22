import Foundation

/// Offsets in 64-unit space. Reach selects a fixed-length arm drawing, never an elongated limb.
public struct HammerTrickPose: Equatable, Sendable {
    public var offsetX = 0.0
    public var offsetY = 0.0
    public var rotation = 0.0
    public var scale = 1.0
    public var opacity = 1.0
    public var handAngle = 0.0
    public var bodyOffsetX = 0.0
    public var bodyOffsetY = 0.0
    public var bodyScaleY = 1.0
    public var bodyAngle = 0.0
    public var turnAmount = 0.0
    public var reachAmount = 0.0
    public var freeArmAngle = 0.0
    public var headAngle = 0.0
    public var headOffsetX = 0.0
    public var headOffsetY = 0.0
    public var headScaleX = 1.0
    public var gazeX = 0.0
    public var gazeY = 0.0
    public var catchGlow = 0.0
    public var trailStrength = 0.0
    public var isAirborne = false
    public init() {}
}

/// Coordinated silhouette, weight transfer, gaze, and rigid-tool key poses.
public enum HammerTrick: String, CaseIterable, Sendable {
    case toss, recall, snatchRecall
    public var duration: Double {
        switch self {
        case .toss: 1.55
        case .recall: 2.7
        case .snatchRecall: 3.1
        }
    }
    public var releaseTime: Double {
        switch self {
        case .toss: 0.27
        case .recall: 0.45
        case .snatchRecall: 0
        }
    }
    public var catchTime: Double {
        switch self {
        case .toss: 1.10
        case .recall: 1.5
        case .snatchRecall: 1.9
        }
    }

    public func pose(at time: Double) -> HammerTrickPose {
        guard time.isFinite, time > 0, time < duration else { return HammerTrickPose() }
        if self == .snatchRecall { return snatchRecallPose(at: time) }
        var pose = self == .recall ? recallBody(at: time) : tossBody(at: time)
        if self == .recall, time < releaseTime {
            pose.opacity = 1 - smooth((time / releaseTime - 0.55) / 0.45)
        }
        if time >= releaseTime, time < catchTime {
            let flight = (time - releaseTime) / (catchTime - releaseTime)
            pose.isAirborne = true
            if self == .toss {
                pose.offsetX = 3 * sin(.pi * flight)
                pose.offsetY = 220 * flight * (1 - flight)
                pose.rotation = 6 * .pi * (flight - 1)
                pose.trailStrength = channel(time, [(0.27,0),(0.34,0.85),(0.685,0.06),(1.02,0.95),(1.10,0)])
            } else {
                let approach = pow(flight, 1.65)
                pose.offsetX = 140 * (1 - approach)
                pose.offsetY = 65 * (1 - approach) + 10 * sin(.pi * flight)
                pose.rotation = -1.4 * (1 - approach)
                pose.scale = 0.45 + 0.55 * approach
                pose.opacity = smooth((time - releaseTime) / 0.1)
                pose.trailStrength = channel(time, [(0.45,0),(0.7,0.25),(1.2,0.75),(1.43,1),(1.5,0)])
            }
        }
        return pose
    }

    private func snatchRecallPose(at t: Double) -> HammerTrickPose {
        // A short loss-of-balance beat precedes the familiar fixed-length reach.
        let recallTime = t < catchTime ? max(0, (t - 0.65) * 1.2) : 1.5 + t - catchTime
        var p = recallBody(at: recallTime)
        let surprise = channel(t, [(0,0),(0.16,1),(0.35,0.65),(0.65,0)])
        p.bodyOffsetX -= 1.1 * surprise
        p.bodyAngle += 0.065 * surprise
        p.headAngle -= 0.07 * surprise
        p.gazeX = max(p.gazeX, channel(t, [(0,0),(0.18,1),(0.65,1),(0.9,0)]))
        if t >= catchTime {
            // Stronger compression on impact, with a delayed head follow-through.
            p.bodyOffsetY *= 1.35
            p.bodyScaleY = 1 + (p.bodyScaleY - 1) * 1.3
            p.headOffsetY *= 1 + 0.3 * smooth((t - catchTime) / 0.14)
            p.catchGlow = min(0.25, p.catchGlow * 1.12)
        }
        if t < catchTime {
            p.isAirborne = true
            let outward = smooth(t / 0.35)
            let returning = pow(max(0, (t - 0.7) / (catchTime - 0.7)), 2.2)
            let distance = outward * (1 - returning)
            p.offsetX = 140 * distance
            p.offsetY = 18 * distance + 7 * sin(.pi * outward) * (1 - returning)
            p.rotation = -1.4 * distance
            p.trailStrength = channel(t, [(0,0),(0.12,0.85),(0.35,0),(0.7,0),(1.4,0.4),(1.82,1),(1.9,0)])
        }
        return p
    }

    private func recallBody(at t: Double) -> HammerTrickPose {
        var p = HammerTrickPose()
        // Plant and turn before waiting; recoil moves the center of mass, not the arm length.
        p.turnAmount = channel(t, [(0,0),(0.45,1),(1.7,1),(2.45,0),(2.7,0)])
        p.reachAmount = channel(t, [(0,0),(0.45,1),(1.5,1),(1.64,0.55),(2.05,0.35),(2.55,0)])
        p.bodyOffsetX = channel(t, [(0,0),(0.45,3),(1.5,3),(1.64,1.5),(1.92,2),(2.7,0)])
        p.bodyOffsetY = channel(t, [(0,0),(0.23,-0.45),(0.45,0),(1.5,0),(1.64,-1.1),(1.93,0.2),(2.7,0)])
        p.bodyScaleY = channel(t, [(0,1),(0.23,0.97),(0.45,1),(1.5,1),(1.64,0.94),(1.93,1.015),(2.7,1)])
        p.bodyAngle = channel(t, [(0,0),(0.45,-0.1),(1.5,-0.1),(1.64,0.055),(1.93,-0.025),(2.7,0)])
        p.handAngle = channel(t, [(0,0),(0.45,-0.55),(1.5,-0.55),(1.64,-0.15),(2.1,-0.22),(2.7,0)])
        p.freeArmAngle = channel(t, [(0,0),(0.45,-0.3),(1.5,-0.3),(1.68,0.18),(2.7,0)])
        // Head follows body slightly later, including its catch recoil.
        p.headOffsetX = channel(t, [(0,0),(0.5,0.8),(1.52,0.8),(1.7,-0.35),(2.05,0.3),(2.7,0)])
        p.headOffsetY = channel(t, [(0,0),(0.5,0.3),(1.52,0.3),(1.7,-0.5),(2.05,0.2),(2.7,0)])
        p.headScaleX = 1 - 0.08 * p.turnAmount
        p.headAngle = channel(t, [(0,0),(0.35,-0.06),(1.5,-0.06),(1.7,0.055),(2.1,-0.02),(2.7,0)])
        p.gazeX = channel(t, [(0,0),(0.2,1),(1.5,1),(1.8,0.35),(2.35,0),(2.7,0)])
        p.gazeY = channel(t, [(0,0),(0.3,0.55),(0.9,0.55),(1.5,0),(2.7,0)])
        p.catchGlow = channel(t, [(0,0),(1.55,0),(1.68,0.22),(1.95,0),(2.7,0)])
        return p
    }

    private func tossBody(at t: Double) -> HammerTrickPose {
        var p = HammerTrickPose()
        // A compact wind-up and full-body launch sell weight without stretching the arm.
        p.bodyOffsetY = channel(t, [(0,0),(0.15,-1.45),(0.27,1.7),(0.48,0),(1.10,0),(1.20,-1.4),(1.35,0.25),(1.55,0)])
        p.bodyScaleY = channel(t, [(0,1),(0.15,0.93),(0.27,1.045),(0.48,1),(1.10,1),(1.20,0.92),(1.35,1.015),(1.55,1)])
        p.bodyOffsetX = channel(t, [(0,0),(0.15,-0.65),(0.27,0.6),(0.52,0),(1.10,0),(1.20,-0.45),(1.55,0)])
        p.bodyAngle = channel(t, [(0,0),(0.15,0.09),(0.27,-0.10),(0.52,0),(1.10,0),(1.20,0.065),(1.55,0)])
        p.handAngle = channel(t, [(0,0),(0.15,0.3),(0.27,-0.75),(0.65,-0.3),(1.10,0.1),(1.20,0.4),(1.55,0)])
        p.freeArmAngle = channel(t, [(0,0),(0.15,-0.22),(0.30,0.35),(0.58,0),(1.20,0.2),(1.55,0)])
        // The head lags the torso on both launch and catch, and tracks the airborne hammer.
        p.headOffsetY = channel(t, [(0,0),(0.17,-0.45),(0.31,0.8),(0.69,0.55),(1.10,0),(1.24,-0.5),(1.55,0)])
        p.headAngle = channel(t, [(0,0),(0.17,0.05),(0.40,-0.10),(0.82,-0.06),(1.10,0),(1.24,0.06),(1.55,0)])
        p.gazeY = channel(t, [(0,0),(0.27,0.5),(0.52,1),(0.80,1),(1.10,0),(1.55,0)])
        p.catchGlow = channel(t, [(0,0),(1.10,0),(1.19,0.18),(1.38,0),(1.55,0)])
        return p
    }

    private func channel(_ time: Double, _ keys: [(Double, Double)]) -> Double {
        guard let first = keys.first, let last = keys.last else { return 0 }
        if time <= first.0 { return first.1 }
        for index in 1..<keys.count where time <= keys[index].0 {
            let a = keys[index - 1], b = keys[index]
            return a.1 + (b.1 - a.1) * smooth((time - a.0) / (b.0 - a.0))
        }
        return last.1
    }

    private func smooth(_ value: Double) -> Double {
        let value = min(max(value, 0), 1)
        return value * value * (3 - 2 * value)
    }
}
