import AppKit

/// What the menu bar shows to announce a calendar event.
struct EventBannerContent: Equatable {
    var title: String
    /// The pill beside the title: how long until it starts, or until when it runs.
    var when: String
    /// Where, when the event says so (a link is left out: the video icon stands for it).
    var place: String?
    /// Minutes to the start; nil once it has started.
    var minutes: Int?
    /// How much of the wait has passed (0…1), for the ring.
    var progress: Double
    var color: NSColor
    var hasMeeting: Bool

    static func make(_ event: CalendarEvent, now: Date, use24Hour: Bool, leadMinutes: Int) -> EventBannerContent {
        let time = use24Hour ? "HH:mm" : "h:mm a"
        let remaining = event.start.timeIntervalSince(now)
        let minutes = remaining > 0 ? Int((remaining / 60).rounded(.up)) : nil
        let when: String
        if let minutes {
            let wait = minutes >= 60 ? "tra \(minutes / 60) h\(minutes % 60 > 0 ? " \(minutes % 60) min" : "")" : "tra \(minutes) min"
            when = "\(wait) · \(DateText.string(event.start, time))"
        } else {
            when = "in corso · fino alle \(DateText.string(event.end, time))"
        }
        var place = event.location?.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) }
        if let text = place, text.isEmpty || text.lowercased().hasPrefix("http") { place = nil }
        if let text = place, text.count > 32 { place = String(text.prefix(31)).trimmingCharacters(in: .whitespaces) + "…" }
        let lead = Double(max(leadMinutes, 1)) * 60
        return EventBannerContent(title: event.title, when: when, place: place, minutes: minutes,
                                  progress: minutes == nil ? 1 : min(max(1 - remaining / lead, 0), 1),
                                  color: event.color, hasMeeting: event.meetingURL != nil)
    }
}

extension MenubarRenderer {
    private static let bannerTitleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let bannerPillFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private static let bannerPlaceFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    private static let bannerRing: CGFloat = 16
    /// Spaces between the pieces of the line: ring, title, pill, place, video icon.
    private static let bannerGap: CGFloat = 7
    private static let bannerPillPadding: CGFloat = 7
    private static let bannerVideo: CGFloat = 17
    /// Room kept free at the right end, toward the clock.
    private static let bannerTrailing: CGFloat = 4
    /// Pause before a long title starts scrolling, and its speed.
    private static let marqueeDelay: Double = 1.4
    private static let marqueeSpeed: Double = 28
    private static let marqueeGap: CGFloat = 36

    /// Width of everything on the line except the title.
    private static func bannerFixedWidth(_ content: EventBannerContent) -> CGFloat {
        var width = 2 + bannerRing + bannerGap + bannerGap + measureText(content.when, bannerPillFont) + bannerPillPadding * 2
        if let place = content.place { width += bannerGap + measureText(place, bannerPlaceFont) }
        if content.hasMeeting { width += bannerGap + bannerVideo }
        return width + bannerTrailing
    }

    /// The width a banner would like (its full line), before the room in the menu bar limits it.
    static func idealBannerWidth(_ contents: [EventBannerContent]) -> CGFloat {
        ceil(contents.map { bannerFixedWidth($0) + measureText($0.title, bannerTitleFont) }.max() ?? 120)
    }

    /// One frame of the announcement. `reveal` 0 shows the modules, 1 the banner: in between the modules leave one after
    /// the other, left to right, rising and fading, and the banner rises into place. `crossfade` blends `current` into
    /// `next` (several events at once). `elapsed` drives the scrolling of a title too long for the width.
    static func bannerImage(modules: [ModuleID], context: Context, width: CGFloat, reveal: CGFloat,
                            current: EventBannerContent?, next: EventBannerContent? = nil, crossfade: CGFloat = 0,
                            elapsed: Double = 0) -> NSImage {
        var options = context.options
        options.forceColor = true // the calendar's color needs a colored image; text stays adaptive (labelColor)
        var colored = context
        colored.options = options
        let segments = modules.map { segment(for: $0, context: colored) }
        let modulesWidth = segments.map(\.width).reduce(0, +) + segmentGap * CGFloat(max(segments.count - 1, 0))

        let image = NSImage(size: NSSize(width: max(width, 1), height: height), flipped: false) { bounds in
            guard let cg = NSGraphicsContext.current?.cgContext else { return true }
            cg.clip(to: bounds)
            // Modules: staggered exit.
            var x = (bounds.width - modulesWidth) / 2
            let count = CGFloat(max(segments.count, 1))
            for (index, segment) in segments.enumerated() {
                let delay = CGFloat(index) / count * 0.45
                let t = ease(min(max((reveal - delay) / 0.5, 0), 1))
                if t < 1 {
                    cg.saveGState()
                    cg.setAlpha(1 - t)
                    cg.translateBy(x: 0, y: t * 10)
                    segment.draw(NSRect(x: x, y: 0, width: segment.width, height: height))
                    cg.restoreGState()
                }
                x += segment.width + segmentGap
            }
            // Banner: rises in once most modules have left.
            let shown = ease(min(max((reveal - 0.45) / 0.55, 0), 1))
            guard shown > 0 else { return true }
            for (content, alpha, lift) in [(current, 1 - crossfade, crossfade * 8), (next, crossfade, (crossfade - 1) * 8)] {
                guard let content, alpha > 0.01 else { continue }
                cg.saveGState()
                cg.setAlpha(shown * alpha)
                cg.translateBy(x: 0, y: -(1 - shown) * 10 + lift)
                drawBanner(content, in: bounds, elapsed: elapsed)
                cg.restoreGState()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// One line, right-aligned toward the clock: countdown ring, title, a pill with when, the place, the video icon.
    private static func drawBanner(_ content: EventBannerContent, in bounds: NSRect, elapsed: Double) {
        let fixed = bannerFixedWidth(content)
        let titleWidth = measureText(content.title, bannerTitleFont)
        let titleRoom = max(min(titleWidth, bounds.width - fixed), 10)
        var x = max(bounds.width - fixed - titleRoom, 0) + 2

        // Countdown ring in the calendar's color, minutes inside (a dot once the event has started).
        let ring = NSRect(x: x, y: (height - bannerRing) / 2, width: bannerRing, height: bannerRing).insetBy(dx: 1.1, dy: 1.1)
        let track = NSBezierPath(ovalIn: ring)
        track.lineWidth = 2
        content.color.withAlphaComponent(0.28).setStroke()
        track.stroke()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: ring.midX, y: ring.midY), radius: ring.width / 2, startAngle: 90,
                      endAngle: 90 - 360 * CGFloat(min(max(content.progress, 0.02), 1)), clockwise: true)
        arc.lineWidth = 2
        arc.lineCapStyle = .round
        content.color.setStroke()
        arc.stroke()
        if let minutes = content.minutes {
            let text = (minutes > 99 ? "99+" : "\(minutes)") as NSString
            let font = NSFont.monospacedDigitSystemFont(ofSize: minutes > 9 ? 7 : 8, weight: .bold)
            let size = text.size(withAttributes: [.font: font])
            text.draw(at: NSPoint(x: ring.midX - size.width / 2, y: ring.midY - size.height / 2 + 0.2),
                      withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
        } else {
            content.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: ring.midX - 3, y: ring.midY - 3, width: 6, height: 6)).fill()
        }
        x += bannerRing + bannerGap

        // Title, scrolling in its own column when the room is short.
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: bannerTitleFont, .foregroundColor: NSColor.labelColor]
        let title = content.title as NSString
        let titleY = centered(bannerTitleFont)
        if titleWidth <= titleRoom {
            title.draw(at: NSPoint(x: x, y: titleY), withAttributes: titleAttributes)
        } else {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: x, y: 0, width: titleRoom, height: height)).addClip()
            let cycle = titleWidth + marqueeGap
            let offset = CGFloat(max(elapsed - marqueeDelay, 0) * marqueeSpeed).truncatingRemainder(dividingBy: cycle)
            title.draw(at: NSPoint(x: x - offset, y: titleY), withAttributes: titleAttributes)
            title.draw(at: NSPoint(x: x - offset + cycle, y: titleY), withAttributes: titleAttributes)
            NSGraphicsContext.restoreGraphicsState()
        }
        x += titleRoom + bannerGap

        // Pill: tinted with the calendar's color.
        let pillText = content.when as NSString
        let pillWidth = measureText(content.when, bannerPillFont) + bannerPillPadding * 2
        let pill = NSRect(x: x, y: (height - 16) / 2, width: pillWidth, height: 16)
        content.color.withAlphaComponent(0.24).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
        pillText.draw(at: NSPoint(x: pill.minX + bannerPillPadding, y: centered(bannerPillFont)),
                      withAttributes: [.font: bannerPillFont, .foregroundColor: NSColor.labelColor])
        x += pillWidth

        if let place = content.place {
            x += bannerGap
            (place as NSString).draw(at: NSPoint(x: x, y: centered(bannerPlaceFont)),
                                     withAttributes: [.font: bannerPlaceFont, .foregroundColor: NSColor.labelColor.withAlphaComponent(0.6)])
            x += measureText(place, bannerPlaceFont)
        }

        if content.hasMeeting, let video = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) {
            x += bannerGap
            let box = NSRect(x: x, y: (height - video.size.height) / 2, width: video.size.width, height: video.size.height)
            let tinted = NSImage(size: video.size, flipped: false) { rect in
                video.draw(in: rect)
                content.color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: box)
        }
    }

    /// Where to draw one line of `font` so it sits in the middle of the menu bar.
    private static func centered(_ font: NSFont) -> CGFloat {
        let line = ceil(font.ascender - font.descender + font.leading)
        return ((height - line) / 2).rounded(.toNearestOrAwayFromZero)
    }

    /// Whether a title needs scrolling at this width (the menu bar then redraws while it moves).
    static func bannerScrolls(_ content: EventBannerContent, width: CGFloat) -> Bool {
        measureText(content.title, bannerTitleFont) > width - bannerFixedWidth(content)
    }

    static func ease(_ t: CGFloat) -> CGFloat {
        // Ease in-out cubic: a calm start and a soft landing.
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private static func measureText(_ text: String, _ font: NSFont, kern: CGFloat = 0) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font, .kern: kern]).width)
    }
}
