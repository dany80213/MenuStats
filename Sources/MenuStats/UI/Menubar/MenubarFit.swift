import CoreGraphics

/// How MenuStats shrinks when the menu bar has no room, one step at a time and always in the same order:
/// the bar as configured, then without labels (only if that saves room, otherwise the labels stay), then one module
/// fewer at a time from the end of the list, down to the first module alone. Every step is narrower than the one before.
enum MenubarFit {
    struct Step: Equatable, CustomStringConvertible {
        /// How many of the configured modules are shown (the first ones in the user's order).
        var moduleCount: Int
        var labels: Bool
        var description: String { "\(moduleCount) moduli\(labels ? " con etichette" : "")" }
    }

    /// Room kept free beside the notch (the overflow arrow macOS adds sits by Control Center, right of MenuStats).
    static let reserve: CGFloat = 10
    /// Extra room a wider step needs before MenuStats grows back, so values that change width (network rates,
    /// percentages) don't make it flip between two steps.
    static let growMargin: CGFloat = 16

    /// The steps for `count` modules, with their widths. `width` measures a step (the menu bar items it needs).
    static func ladder(count: Int, labelsConfigured: Bool, width: (Step) -> CGFloat) -> [(step: Step, width: CGFloat)] {
        guard count > 0 else { return [(Step(moduleCount: 0, labels: labelsConfigured), 0)] }
        let full = Step(moduleCount: count, labels: labelsConfigured)
        var candidates = [full]
        // Labels go first, but only when that saves room: with some styles the bar is as wide without them.
        var labels = labelsConfigured
        if labelsConfigured, width(Step(moduleCount: count, labels: false)) < width(full) - 0.5 {
            candidates.append(Step(moduleCount: count, labels: false))
            labels = false
        }
        if count > 1 { candidates += (1..<count).reversed().map { Step(moduleCount: $0, labels: labels) } }
        var ladder: [(step: Step, width: CGFloat)] = []
        for step in candidates {
            let measured = width(step)
            // A step that saves no room is skipped: without labels some styles are as wide, or wider.
            if let last = ladder.last, measured >= last.width - 0.5 { continue }
            ladder.append((step, measured))
        }
        return ladder
    }

    /// The step to show for `room` points, starting from step `current`: the widest that fits. Shrinking happens at
    /// once; growing back needs `growMargin` more room, and goes to the widest step that clears it.
    static func choose(_ ladder: [(step: Step, width: CGFloat)], room: CGFloat, current: Int) -> Int {
        guard !ladder.isEmpty else { return 0 }
        let current = min(max(current, 0), ladder.count - 1)
        if ladder[current].width > room {
            return ladder.firstIndex { $0.width <= room } ?? ladder.count - 1
        }
        let wider = ladder.firstIndex { $0.width <= room - growMargin } ?? current
        return min(wider, current)
    }

    /// With several displays the items follow the active one. When its menu bar is hidden (an app in full screen,
    /// or the bar set to hide automatically) macOS parks them just above that display's top edge: that isn't lack
    /// of room, and nothing can be judged until the bar shows again. Frames in Cocoa coordinates (origin bottom left).
    static func isOverHiddenMenuBar(_ frame: CGRect, screens: [CGRect]) -> Bool {
        guard !screens.contains(where: { $0.intersects(frame) }) else { return false }
        return screens.contains { $0.minX <= frame.midX && frame.midX <= $0.maxX && abs(frame.minY - $0.maxY) <= frame.height * 2 }
    }

    /// Points between the notch's right edge and the right edge of MenuStats' items: what they may use.
    /// nil on displays without a notch, where the room depends on the front app's menus and can't be measured.
    static func room(rightEdge: CGFloat, notchRightEdge: CGFloat?) -> CGFloat? {
        notchRightEdge.map { rightEdge - $0 - reserve }
    }
}
