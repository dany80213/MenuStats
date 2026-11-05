import AppKit

/// What the menu bar shows to announce a calendar event.
struct EventBannerContent: Equatable {
    var title: String
    /// Small line above the title: when, until when, where.
    var detail: String
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
        var parts: [String] = []
        if let minutes {
            parts.append(minutes >= 60 ? "TRA \(minutes / 60) H \(minutes % 60 > 0 ? "\(minutes % 60) MIN" : "")".trimmingCharacters(in: .whitespaces)
                                       : "TRA \(minutes) MIN")
            parts.append("\(DateText.string(event.start, time))–\(DateText.string(event.end, time))")
        } else {
            parts.append("ORA")
            parts.append("FINO ALLE \(DateText.string(event.end, time))")
        }
        if let location = event.location?.split(separator: "\n").first.map(String.init), !location.lowercased().hasPrefix("http") {
            parts.append(location)
        } else if event.meetingURL != nil {
            parts.append("VIDEOCHIAMATA")
        }
        let lead = Double(max(leadMinutes, 1)) * 60
        return EventBannerContent(title: event.title, detail: parts.joined(separator: " · ").uppercased(), minutes: minutes,
                                  progress: minutes == nil ? 1 : min(max(1 - remaining / lead, 0), 1),
                                  color: event.color, hasMeeting: event.meetingURL != nil)
    }
}

extension MenubarRenderer {
    private static let bannerTitleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    private static let bannerDetailFont = NSFont.systemFont(ofSize: 8, weight: .semibold)
    private static let bannerRing: CGFloat = 17
    private static let bannerTextX: CGFloat = 23
    /// Pause before a long title starts scrolling, and its speed.
    private static let marqueeDelay: Double = 1.4
    private static let marqueeSpeed: Double = 28
    private static let marqueeGap: CGFloat = 36

    /// The width a banner would like (its full text), before the room in the menu bar limits it.
    static func idealBannerWidth(_ contents: [EventBannerContent]) -> CGFloat {
        let text = contents.map { max(measureText($0.title, bannerTitleFont), measureText($0.detail, bannerDetailFont, kern: 0.4)) + ($0.hasMeeting ? 16 : 0) }
        return ceil(bannerTextX + (text.max() ?? 80) + 3)
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

    private static func drawBanner(_ content: EventBannerContent, in bounds: NSRect, elapsed: Double) {
        // Countdown ring in the calendar's color, minutes inside (a dot once the event has started).
        let ring = NSRect(x: 2, y: (height - bannerRing) / 2, width: bannerRing, height: bannerRing).insetBy(dx: 1.25, dy: 1.25)
        let track = NSBezierPath(ovalIn: ring)
        track.lineWidth = 2.2
        content.color.withAlphaComponent(0.28).setStroke()
        track.stroke()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: ring.midX, y: ring.midY), radius: ring.width / 2, startAngle: 90,
                      endAngle: 90 - 360 * CGFloat(min(max(content.progress, 0.02), 1)), clockwise: true)
        arc.lineWidth = 2.2
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

        let trailing: CGFloat = content.hasMeeting ? 16 : 0
        let column = NSRect(x: bannerTextX, y: 0, width: max(bounds.width - bannerTextX - trailing - 2, 10), height: height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: column).addClip()
        let detailAttributes: [NSAttributedString.Key: Any] = [.font: bannerDetailFont, .kern: 0.4,
                                                              .foregroundColor: NSColor.labelColor.withAlphaComponent(0.6)]
        (content.detail as NSString).draw(at: NSPoint(x: column.minX, y: 12), withAttributes: detailAttributes)
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: bannerTitleFont, .foregroundColor: NSColor.labelColor]
        let title = content.title as NSString
        let titleWidth = measureText(content.title, bannerTitleFont)
        if titleWidth <= column.width {
            title.draw(at: NSPoint(x: column.minX, y: 0), withAttributes: titleAttributes)
        } else {
            // Too long: after a pause it scrolls left in a loop, with a gap between the copies.
            let cycle = Double(titleWidth + marqueeGap)
            let offset = CGFloat(max(elapsed - marqueeDelay, 0) * marqueeSpeed).truncatingRemainder(dividingBy: CGFloat(cycle))
            title.draw(at: NSPoint(x: column.minX - offset, y: 0), withAttributes: titleAttributes)
            title.draw(at: NSPoint(x: column.minX - offset + titleWidth + marqueeGap, y: 0), withAttributes: titleAttributes)
        }
        NSGraphicsContext.restoreGraphicsState()

        if content.hasMeeting, let video = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) {
            let box = NSRect(x: bounds.width - 15, y: (height - video.size.height) / 2, width: video.size.width, height: video.size.height)
            let tinted = NSImage(size: video.size, flipped: false) { rect in
                video.draw(in: rect)
                content.color.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: box)
        }
    }

    /// Whether a title needs scrolling at this width (the menu bar then redraws while it moves).
    static func bannerScrolls(_ content: EventBannerContent, width: CGFloat) -> Bool {
        measureText(content.title, bannerTitleFont) > width - bannerTextX - (content.hasMeeting ? 16 : 0) - 2
    }

    static func ease(_ t: CGFloat) -> CGFloat {
        // Ease in-out cubic: a calm start and a soft landing.
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private static func measureText(_ text: String, _ font: NSFont, kern: CGFloat = 0) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font, .kern: kern]).width)
    }
}
