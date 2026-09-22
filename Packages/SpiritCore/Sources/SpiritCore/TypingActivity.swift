import Foundation

/// Uses only aggregate key-down counts; no key codes or typed text are collected.
public struct TypingActivity: Sendable {
    private var previousCount: UInt32?
    private var burstStart = 0.0
    private var lastInput = -Double.infinity
    private var burstCount: UInt32 = 0

    public init() {}

    public mutating func sample(count: UInt32, at time: TimeInterval, enabled: Bool = true) -> Bool {
        defer { previousCount = count }
        guard enabled, let previousCount else {
            burstCount = 0
            lastInput = -.infinity
            return false
        }
        let added = count &- previousCount
        if added > 0 {
            if time - lastInput > 0.9 || (burstCount < 3 && time - burstStart > 1.2) {
                burstStart = time
                burstCount = 0
            }
            burstCount = min(3, burstCount + min(3, added))
            lastInput = time
        }
        return burstCount >= 3 && time - lastInput <= 0.9
    }
}
