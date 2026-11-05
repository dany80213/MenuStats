import AppKit

/// When the menu bar announces an event: `lead` minutes before it starts, then again every `interval` minutes up to
/// `repeats` times in all (never after the start), and optionally once more when it starts. All-day events never.
enum EventAlertPlan {
    static func times(for event: CalendarEvent, leadMinutes: Int, repeats: Int, intervalMinutes: Int, atStart: Bool) -> [Date] {
        guard !event.isAllDay else { return [] }
        let first = event.start.addingTimeInterval(-Double(max(leadMinutes, 0)) * 60)
        var times = (0..<max(repeats, 1)).map { first.addingTimeInterval(Double($0 * max(intervalMinutes, 1)) * 60) }
            .filter { $0 < event.start }
        if atStart { times.append(event.start) }
        return times
    }
}

/// Decides, at each sample, which events the menu bar should announce now. Each alert time fires once; one that was
/// missed by more than `staleAfter` (the Mac was asleep) is skipped rather than shown late.
final class EventAlerts: ObservableObject {
    struct Banner: Equatable {
        var id = UUID()
        var events: [CalendarEvent]
        /// Seconds each event stays on screen.
        var secondsPerEvent: Double
    }

    /// The banner to play now; the menu bar clears it once shown.
    @Published private(set) var pending: Banner?
    static let staleAfter: TimeInterval = 90
    private var fired: Set<String> = []

    func evaluate(_ events: [CalendarEvent], settings: Settings, now: Date = Date()) {
        guard settings.calendarAlerts else { return }
        var due: [CalendarEvent] = []
        for event in events {
            let times = EventAlertPlan.times(for: event, leadMinutes: settings.calendarAlertMinutes, repeats: settings.calendarAlertRepeats,
                                             intervalMinutes: settings.calendarAlertRepeatMinutes, atStart: settings.calendarAlertAtStart)
            for time in times where time <= now {
                let key = "\(event.id)|\(Int(time.timeIntervalSince1970))"
                guard !fired.contains(key) else { continue }
                fired.insert(key)
                if now.timeIntervalSince(time) <= Self.staleAfter, !due.contains(where: { $0.id == event.id }) { due.append(event) }
            }
        }
        // Forget alerts of events long gone.
        if fired.count > 500 { fired.removeAll() }
        guard !due.isEmpty else { return }
        show(due, settings: settings)
    }

    /// Plays a banner now (also the "Prova avviso" button in Settings).
    func show(_ events: [CalendarEvent], settings: Settings) {
        pending = Banner(events: events.sorted { $0.start < $1.start }, secondsPerEvent: Double(max(settings.calendarAlertSeconds, 2)))
    }

    /// "Prova avviso": the next event of the day, or an example when there is none.
    func preview(calendar: CalendarService, settings: Settings) {
        let now = Date()
        let lead = Double(settings.calendarAlertMinutes) * 60
        let next = calendar.upcoming.first { !$0.isAllDay && $0.end > now }
        let example = CalendarEvent(
            id: "prova-\(UUID().uuidString)", title: "Riunione di progetto con il team", start: now.addingTimeInterval(lead),
            end: now.addingTimeInterval(lead + 1800), isAllDay: false, location: "Sala Galileo", notes: nil,
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij"), calendarID: "", calendarTitle: "Lavoro", color: .systemPurple)
        show([next ?? example], settings: settings)
    }

    func finished(_ banner: Banner) {
        if pending?.id == banner.id { pending = nil }
    }
}

/// The day the Date tab shows events for; a click on an announcement sets it to the event's day.
final class CalendarFocus: ObservableObject {
    static let shared = CalendarFocus()
    @Published var day = Date()
}
