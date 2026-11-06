import AppKit
import XCTest
@testable import MenuStats

final class CalendarTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_900_000_000)

    private func event(_ id: String = "e1", startsIn minutes: Double = 10, allDay: Bool = false, title: String = "Riunione",
                       location: String? = "Sala 2", meeting: URL? = nil) -> CalendarEvent {
        let eventStart = start.addingTimeInterval(minutes * 60)
        return CalendarEvent(id: id, title: title, start: eventStart, end: eventStart.addingTimeInterval(1800), isAllDay: allDay,
                             location: location, notes: nil, meetingURL: meeting, calendarID: "c", calendarTitle: "Lavoro", color: .systemBlue)
    }

    func testAlertTimes() {
        let e = event(startsIn: 30)
        let times = EventAlertPlan.times(for: e, leadMinutes: 10, repeats: 3, intervalMinutes: 2, atStart: true)
        XCTAssertEqual(times.map { $0.timeIntervalSince(e.start) / 60 }, [-10, -8, -6, 0])
        // Repeats never go past the start.
        let late = EventAlertPlan.times(for: e, leadMinutes: 3, repeats: 5, intervalMinutes: 2, atStart: false)
        XCTAssertEqual(late.map { $0.timeIntervalSince(e.start) / 60 }, [-3, -1])
        XCTAssertEqual(EventAlertPlan.times(for: event(allDay: true), leadMinutes: 10, repeats: 1, intervalMinutes: 1, atStart: true), [])
    }

    func testEachAlertFiresOnceAndStaleOnesAreSkipped() {
        let settings = Settings.shared
        let saved = (settings.calendarAlerts, settings.calendarAlertMinutes, settings.calendarAlertRepeats, settings.calendarAlertAtStart)
        defer {
            settings.calendarAlerts = saved.0; settings.calendarAlertMinutes = saved.1
            settings.calendarAlertRepeats = saved.2; settings.calendarAlertAtStart = saved.3
        }
        settings.calendarAlerts = true
        settings.calendarAlertMinutes = 10
        settings.calendarAlertRepeats = 1
        settings.calendarAlertAtStart = false
        let alerts = EventAlerts()
        let e = event(startsIn: 10) // its alert is due exactly now
        alerts.evaluate([e], settings: settings, now: start.addingTimeInterval(-60))
        XCTAssertNil(alerts.pending, "not yet")
        alerts.evaluate([e], settings: settings, now: start.addingTimeInterval(5))
        XCTAssertEqual(alerts.pending?.events.map(\.id), ["e1"])
        let banner = alerts.pending!
        alerts.finished(banner)
        alerts.evaluate([e], settings: settings, now: start.addingTimeInterval(20))
        XCTAssertNil(alerts.pending, "fires once")

        // The Mac slept through the alert time: not shown minutes late.
        let other = EventAlerts()
        other.evaluate([event("e2", startsIn: 10)], settings: settings, now: start.addingTimeInterval(300))
        XCTAssertNil(other.pending)
    }

    func testSimultaneousEventsShareOneBanner() {
        let settings = Settings.shared
        let saved = settings.calendarAlertAtStart
        defer { settings.calendarAlertAtStart = saved }
        settings.calendarAlertAtStart = false
        let alerts = EventAlerts()
        let lead = Double(settings.calendarAlertMinutes)
        alerts.evaluate([event("b", startsIn: lead), event("a", startsIn: lead)], settings: settings, now: start.addingTimeInterval(1))
        XCTAssertEqual(alerts.pending?.events.count, 2)
    }

    func testMeetingLinks() {
        XCTAssertEqual(CalendarEvent.meetingLink(in: [nil, "Entra: https://us02web.zoom.us/j/123?pwd=x grazie"])?.host, "us02web.zoom.us")
        XCTAssertEqual(CalendarEvent.meetingLink(in: ["https://meet.google.com/abc-defg-hij"])?.absoluteString, "https://meet.google.com/abc-defg-hij")
        XCTAssertNotNil(CalendarEvent.meetingLink(in: ["<https://teams.microsoft.com/l/meetup-join/19%3a>"]))
        XCTAssertNil(CalendarEvent.meetingLink(in: ["https://example.com/agenda", "Sala riunioni"]))
    }

    func testBannerText() {
        let e = event(startsIn: 10, meeting: URL(string: "https://meet.google.com/x"))
        let before = EventBannerContent.make(e, now: start, use24Hour: true, leadMinutes: 10)
        XCTAssertEqual(before.minutes, 10)
        XCTAssertTrue(before.when.hasPrefix("tra 10 min · "))
        XCTAssertEqual(before.place, "Sala 2")
        XCTAssertTrue(before.hasMeeting)
        let now = EventBannerContent.make(e, now: e.start.addingTimeInterval(5), use24Hour: true, leadMinutes: 10)
        XCTAssertNil(now.minutes)
        XCTAssertTrue(now.when.hasPrefix("in corso · fino alle"))
        XCTAssertEqual(now.progress, 1)
    }

    func testMenubarDrawsTheNewStyles() {
        var options = MenubarOptions(Settings.shared)
        var snapshot = Snapshot()
        snapshot.network = NetworkStats(interface: "en0", ipAddress: "192.168.1.2", downloadRate: 2_400_000, uploadRate: 310_000,
                                        totalDownloaded: 0, totalUploaded: 0)
        var context = MenubarRenderer.Context(snapshot: snapshot, options: options, recent: { _, count in
            (0..<count).map { Double($0) * 1000 } })
        for style in [DateStyle.calendarIcon, .calendarIconTime] {
            options.dateStyle = style
            context.options = options
            XCTAssertGreaterThan(MenubarRenderer.segment(for: .date, context: context).width, 30, "\(style)")
        }
        options.networkStyle = .graphs
        context.options = options
        XCTAssertEqual(MenubarRenderer.segment(for: .network, context: context).width, 40, "graph only")
        options.networkStyle = .graphsValues
        options.graphColors = true
        context.options = options
        XCTAssertGreaterThan(MenubarRenderer.segment(for: .network, context: context).width, 40)
        XCTAssertTrue(options.usesColor, "colored graphs need a colored image")

        let content = EventBannerContent.make(event(title: String(repeating: "Titolo lungo ", count: 8)), now: start,
                                              use24Hour: true, leadMinutes: 10)
        XCTAssertTrue(MenubarRenderer.bannerScrolls(content, width: 200))
        let image = MenubarRenderer.bannerImage(modules: [.cpu, .memory], context: context, width: 200, reveal: 0.6,
                                                current: content, elapsed: 3)
        XCTAssertEqual(image.size.width, 200)
        XCTAssertNotNil(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    func testFocusFilterPicksCalendars() {
        let all = ["lavoro", "casa", "sport", "compleanni"]
        // No Focus filter: the Settings choice.
        XCTAssertEqual(CalendarService.visibleCalendarIDs(all: all, hidden: ["sport"], focus: nil), ["lavoro", "casa", "compleanni"])
        // A filter that shows calendars wins, even over one hidden in Settings.
        XCTAssertEqual(CalendarService.visibleCalendarIDs(all: all, hidden: ["sport"], focus: .show(["sport", "lavoro"])), ["lavoro", "sport"])
        // A filter that hides calendars adds to the ones hidden in Settings.
        XCTAssertEqual(CalendarService.visibleCalendarIDs(all: all, hidden: ["compleanni"], focus: .hide(["casa"])), ["lavoro", "sport"])
    }

    func testFocusPredicateFromMacOS() {
        // As System Settings stores a Calendar filter that keeps one calendar.
        let stored = #"NOT SELF IN {"A896F713-4A08-4CC2-8D5E-D7000A403DFC", "CE2DFC67-69C2-4318-9F80-9FE478760923"}"#
        XCTAssertEqual(FocusCalendarRule.parse(predicate: stored),
                       .hide(["A896F713-4A08-4CC2-8D5E-D7000A403DFC", "CE2DFC67-69C2-4318-9F80-9FE478760923"]))
        XCTAssertEqual(FocusCalendarRule.parse(predicate: #"SELF IN {"X"}"#), .show(["X"]))
        XCTAssertNil(FocusCalendarRule.parse(predicate: "TRUEPREDICATE"))
    }

    func testFocusActionFromMacOS() throws {
        let action: [String: Any] = ["SerializedParameters": [
            "AppIntentDescriptor": ["AppIntentIdentifier": "SetCalendarFocusConfiguration", "BundleIdentifier": "com.apple.iCal"],
            "calendars": ["identifier": "CD58F7DB-90B1-49BC-9F97-F7B6A4CE5856"],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: action, format: .binary, options: 0)
        XCTAssertEqual(FocusCalendarRule.parse(encodedAction: data), .show(["CD58F7DB-90B1-49BC-9F97-F7B6A4CE5856"]))
    }

    func testActiveFocusFromAssertions() {
        let json = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.donotdisturb.mode.default"}}]}],"header":{"version":8}}"#
        XCTAssertEqual(SystemFocusStore.activeModeIDs(assertions: Data(json.utf8)), ["com.apple.donotdisturb.mode.default"])
        // Only invalidated (switched off) assertions: no Focus on.
        let off = #"{"data":[{"storeInvalidationRecords":[{"invalidationAssertion":{}}]}]}"#
        XCTAssertEqual(SystemFocusStore.activeModeIDs(assertions: Data(off.utf8)), [])
        XCTAssertEqual(SystemFocusStore.displayName(modeID: "com.apple.donotdisturb.mode.default", stored: "Do Not Disturb"), "Non disturbare")
        XCTAssertEqual(SystemFocusStore.displayName(modeID: "X-1", stored: "Studio"), "Studio")
    }
}
