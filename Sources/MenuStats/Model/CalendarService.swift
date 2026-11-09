import AppKit
import Combine
import EventKit

/// One calendar event, copied out of EventKit so the UI never touches the store.
struct CalendarEvent: Identifiable, Equatable {
    /// Unique per occurrence (a repeating event has one per day).
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var notes: String?
    /// A video call link found in the event (Zoom, Meet, Teams, FaceTime, Webex…).
    var meetingURL: URL?
    var calendarID: String
    var calendarTitle: String
    var color: NSColor

    func isOngoing(at now: Date) -> Bool { start <= now && now < end }

    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.start == rhs.start && lhs.end == rhs.end
            && lhs.location == rhs.location && lhs.notes == rhs.notes && lhs.calendarID == rhs.calendarID
    }

    /// Video call links people paste in the location, the notes or the URL field.
    static func meetingLink(in texts: [String?]) -> URL? {
        let pattern = #"https://[^\s<>"]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|facetime\.apple\.com|webex\.com|whereby\.com|meet\.jit\.si)[^\s<>"]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range), let swiftRange = Range(match.range, in: text) {
                return URL(string: String(text[swiftRange]))
            }
        }
        return nil
    }
}

struct CalendarInfo: Identifiable, Equatable {
    var id: String
    var title: String
    var source: String
    var color: NSColor
}

/// The Mac's calendars (iCloud, Google, Exchange… whatever is set up in Calendar), read with EventKit.
/// Asks for access once at launch; while authorized it keeps the next days' events and reloads when they change.
final class CalendarService: ObservableObject {
    enum Access: Equatable { case notDetermined, denied, granted }

    @Published private(set) var access: Access = .notDetermined
    @Published private(set) var calendars: [CalendarInfo] = []
    /// Timed and all-day events from now to two days ahead, from the calendars the user keeps on.
    @Published private(set) var upcoming: [CalendarEvent] = []
    /// Bumped when the store changes, so views that read other days reload them.
    @Published private(set) var revision = 0

    private let store = EKEventStore()
    private let settings: Settings
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: Settings) {
        self.settings = settings
        access = Self.currentAccess()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        settings.$hiddenCalendars.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.reload() }
        }.store(in: &cancellables)
        let focus = FocusCalendarFilter.shared
        focus.$status.dropFirst().removeDuplicates().sink { [weak self] status in
            DispatchQueue.main.async {
                self?.reload()
                // Only worth asking when there are calendars to filter.
                if status == .noPermission, self?.access == .granted, let settings = self?.settings {
                    FocusPermissionAlert.showIfNeeded(settings: settings)
                }
            }
        }.store(in: &cancellables)
        focus.setEnabled(settings.calendarFollowFocus)
        settings.$calendarFollowFocus.dropFirst().removeDuplicates().sink { focus.setEnabled($0) }.store(in: &cancellables)
        if access == .granted { start() }
    }

    static func currentAccess() -> Access {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess, .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        }
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// At launch (and from Settings): asks macOS for access the first time; afterwards macOS remembers the answer.
    func requestAccess() {
        guard Self.currentAccess() == .notDetermined else {
            access = Self.currentAccess()
            if access == .granted { start() }
            return
        }
        // A menu bar app has no window in front: bring it forward so the macOS prompt shows.
        NSApp.activate(ignoringOtherApps: true)
        let completion: (Bool, Error?) -> Void = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.access = Self.currentAccess()
                if self.access == .granted { self.start() }
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: completion)
        } else {
            store.requestAccess(to: .event, completion: completion)
        }
    }

    private func start() {
        reload()
        guard timer == nil else { return }
        // Events move out of the window as time passes; the store's change notification covers edits.
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.reload() }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func reload() {
        guard Self.currentAccess() == .granted else { return }
        access = .granted
        store.refreshSourcesIfNecessary()
        calendars = store.calendars(for: .event).map {
            CalendarInfo(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "", color: $0.color ?? .systemBlue)
        }.sorted { ($0.source, $0.title) < ($1.source, $1.title) }
        let now = Date()
        upcoming = events(from: now.addingTimeInterval(-3600 * 12), to: now.addingTimeInterval(86_400 * 2))
        revision += 1
    }

    /// The calendars whose events MenuStats shows: those kept on in Settings, narrowed by the Calendar filter of the
    /// macOS Focus that is on. A filter that names calendars to show wins over Settings (it is an explicit choice);
    /// one that hides calendars hides them on top of those already off in Settings.
    static func visibleCalendarIDs(all: [String], hidden: Set<String>, focus: FocusCalendarRule?) -> [String] {
        switch focus {
        case .show(let shown)?: return all.filter(shown.contains)
        case .hide(let off)?: return all.filter { !hidden.contains($0) && !off.contains($0) }
        case nil: return all.filter { !hidden.contains($0) }
        }
    }

    /// Events between two dates, sorted, from visible calendars; declined invitations and cancelled events left out.
    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard access == .granted else { return [] }
        let all = store.calendars(for: .event)
        let ids = Set(Self.visibleCalendarIDs(all: all.map(\.calendarIdentifier), hidden: settings.hiddenCalendars,
                                              focus: FocusCalendarFilter.shared.rule))
        let visible = all.filter { ids.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visible)
        return store.events(matching: predicate).compactMap { event -> CalendarEvent? in
            guard event.status != .canceled else { return nil }
            if let me = event.attendees?.first(where: \.isCurrentUser), me.participantStatus == .declined { return nil }
            return CalendarEvent(
                id: (event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString)
                    + "@\(Int(event.startDate.timeIntervalSince1970))",
                title: event.title?.isEmpty == false ? event.title! : "Senza titolo",
                start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                location: event.location?.isEmpty == false ? event.location : nil,
                notes: event.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? event.notes : nil,
                meetingURL: CalendarEvent.meetingLink(in: [event.url?.absoluteString, event.location, event.notes]),
                calendarID: event.calendar.calendarIdentifier, calendarTitle: event.calendar.title,
                color: event.calendar.color ?? .systemBlue)
        }.sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    func events(on day: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events(from: start, to: end)
    }

    /// Start of each day of the month around `date` that has at least one event, for the dots in the month grid.
    func busyDays(around date: Date, calendar: Calendar) -> Set<Date> {
        guard access == .granted,
              let month = calendar.dateInterval(of: .month, for: date),
              let start = calendar.date(byAdding: .day, value: -7, to: month.start),
              let end = calendar.date(byAdding: .day, value: 14, to: month.end) else { return [] }
        var days = Set<Date>()
        for event in events(from: start, to: end) {
            var day = calendar.startOfDay(for: event.start)
            // Multi-day events mark every day they cover.
            while day < event.end, day < end {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return days
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
