import Foundation
import CoreGraphics

/// AppKit screen-coordinate placement; tail offset is measured downward from the top.
public struct UsageBubblePlacement: Equatable, Sendable {
    public let frame: CGRect
    public let tailOnLeft: Bool
    public let tailYFromTop: Double

    public init(frame: CGRect, tailOnLeft: Bool, tailYFromTop: Double) {
        self.frame = frame
        self.tailOnLeft = tailOnLeft
        self.tailYFromTop = tailYFromTop
    }

    public static func place(characterFrame: CGRect, visibleFrames: [CGRect],
                             size: CGSize = CGSize(width: 320, height: 200)) -> UsageBubblePlacement {
        let character = characterFrame.standardized
        let center = CGPoint(x: character.midX, y: character.midY)
        let screens = visibleFrames.filter { !$0.isNull && !$0.isInfinite }.map(\.standardized)
        let containing = screens.first { $0.contains(center) }
        var bestIntersection: CGRect?
        var bestArea: CGFloat = 0
        for screen in screens {
            let intersection = screen.intersection(character)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            if area > bestArea { bestArea = area; bestIntersection = screen }
        }
        guard let screen = containing ?? bestIntersection ?? screens.first else {
            let width = max(0, size.width)
            let height = max(0, size.height)
            return UsageBubblePlacement(frame: CGRect(x: character.maxX + 6, y: character.midY - height / 2,
                                                       width: width, height: height),
                                        tailOnLeft: true, tailYFromTop: Double(height / 2))
        }

        // When a screen is smaller than its padding, collapse safely at its center.
        let paddingX = min(8, screen.width / 2)
        let paddingY = min(8, screen.height / 2)
        let available = screen.insetBy(dx: paddingX, dy: paddingY)
        let width = min(max(0, size.width), max(0, available.width))
        let height = min(max(0, size.height), max(0, available.height))
        let rightSpace = available.maxX - character.maxX - 6
        let leftSpace = character.minX - available.minX - 6
        let onRight = rightSpace >= width || (leftSpace < width && rightSpace >= leftSpace)
        let desiredX = onRight ? character.maxX + 6 : character.minX - 6 - width
        let x = min(max(desiredX, available.minX), available.maxX - width)
        let y = min(max(character.midY - height / 2, available.minY), available.maxY - height)
        let frame = CGRect(x: x, y: y, width: width, height: height)
        let tailInset = min(24, height / 2)
        let tailY = min(max(frame.maxY - character.midY, tailInset), height - tailInset)
        return UsageBubblePlacement(frame: frame, tailOnLeft: onRight, tailYFromTop: Double(tailY))
    }
}
