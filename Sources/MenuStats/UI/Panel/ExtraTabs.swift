import SwiftUI

// MARK: - Date

struct DateTab: View {
    @ObservedObject var weather: WeatherService
    @ObservedObject var calendarService: CalendarService
    @ObservedObject private var focusFilter = FocusCalendarFilter.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var focus = CalendarFocus.shared
    @State private var monthOffset = 0

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "it_IT")
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    var body: some View {
        VStack(spacing: 8) {
            Card {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let now = context.date
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DateText.string(now, settings.use24Hour ? "HH:mm:ss" : "h:mm:ss a"))
                                .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(DateText.string(now, "EEEE d MMMM yyyy").capitalized(with: Locale(identifier: "it_IT")))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            badge("Settimana \(calendar.component(.weekOfYear, from: now))")
                            let day = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
                            let total = calendar.range(of: .day, in: .year, for: now)?.count ?? 365
                            Text("Giorno \(day) di \(total)").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if settings.calendarEvents, calendarService.access == .granted, let next = nextEvent {
                NextEventCard(event: next, use24Hour: settings.use24Hour)
            }

            Card {
                MonthCalendar(calendar: calendar, monthOffset: $monthOffset,
                              selected: settings.calendarEvents ? $focus.day : nil,
                              busyDays: settings.calendarEvents ? busyDays : [])
            }

            if settings.calendarEvents { eventsCard }

            if let today = weather.report?.today, let sunrise = today.sunrise, let sunset = today.sunset {
                Card(title: "Sole", trailing: weather.report?.location.name) {
                    HStack(spacing: 18) {
                        sunItem("sunrise.fill", "Alba", sunrise)
                        sunItem("sunset.fill", "Tramonto", sunset)
                        let light = Int(sunset.timeIntervalSince(sunrise) / 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Luce").font(.system(size: 10.5)).foregroundStyle(.secondary)
                            Text("\(light / 60) h \(light % 60) min").font(.system(size: 13, weight: .medium)).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var nextEvent: CalendarEvent? {
        let now = Date()
        return calendarService.upcoming.first { !$0.isAllDay && $0.end > now && $0.start.timeIntervalSince(now) < 86_400 }
    }

    private var busyDays: Set<Date> {
        _ = calendarService.revision
        let month = calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
        return calendarService.busyDays(around: month, calendar: calendar)
    }

    @ViewBuilder private var eventsCard: some View {
        switch calendarService.access {
        case .granted:
            let _ = calendarService.revision
            let events = calendarService.events(on: focus.day, calendar: calendar)
            let title = calendar.isDateInToday(focus.day) ? "Oggi"
                : calendar.isDateInTomorrow(focus.day) ? "Domani"
                : DateText.string(focus.day, "EEEE d MMMM").capitalized(with: DateText.locale)
            Card(title: title, trailing: events.isEmpty ? nil : (events.count == 1 ? "1 impegno" : "\(events.count) impegni")) {
                if events.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.checkmark").font(.system(size: 18)).foregroundStyle(.secondary)
                        Text("Nessun impegno").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(events) { EventRow(event: $0, use24Hour: settings.use24Hour) }
                    }
                }
                if case .active(let active) = focusFilter.status, active.calendars != nil {
                    Label("\(active.name): solo i calendari del suo filtro", systemImage: "moon.fill")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .notDetermined:
            Card(title: "Calendario") {
                Text("Collega il calendario del Mac per vedere qui i tuoi impegni e ricevere un avviso nella barra poco prima che inizino.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Collega il calendario") { calendarService.requestAccess() }
            }
        case .denied:
            Card(title: "Calendario") {
                Text("MenuStats non ha accesso ai calendari. Puoi consentirlo in Impostazioni di Sistema ▸ Privacy e sicurezza ▸ Calendari.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Apri Impostazioni di Sistema…") { CalendarService.openPrivacySettings() }
            }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Palette.color(0).opacity(0.15)))
            .foregroundStyle(Palette.color(0))
    }

    private func sunItem(_ symbol: String, _ title: String, _ date: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).symbolRenderingMode(.multicolor).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary)
                Text(DateText.string(date, settings.use24Hour ? "HH:mm" : "h:mm a")).font(.system(size: 13, weight: .medium)).monospacedDigit()
            }
        }
    }
}

/// The next event, with a live countdown.
private struct NextEventCard: View {
    var event: CalendarEvent
    var use24Hour: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let ongoing = event.isOngoing(at: now)
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: event.color)).frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ongoing ? "IN CORSO" : "PROSSIMO IMPEGNO · \(Self.countdown(to: event.start, now: now))")
                        .font(.system(size: 9.5, weight: .semibold)).kerning(0.4)
                        .foregroundStyle(Color(nsColor: event.color))
                    Text(event.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(EventRow.timeRange(event, use24Hour: use24Hour) + (event.location.map { " · \($0)" } ?? ""))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let url = event.meetingURL {
                    Button { NSWorkspace.shared.open(url) } label: { Label("Partecipa", systemImage: "video.fill") }
                        .controlSize(.small).buttonStyle(.borderedProminent).tint(Color(nsColor: event.color))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: event.color).opacity(0.12)))
        }
    }

    static func countdown(to start: Date, now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "TRA \(max(minutes, 0)) MIN" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "TRA \(hours) H" : "TRA \(hours) H \(rest) MIN"
    }
}

/// One event of the selected day.
struct EventRow: View {
    var event: CalendarEvent
    var use24Hour: Bool

    var body: some View {
        let now = Date()
        let past = event.end < now
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color(nsColor: event.color)).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                    if event.isOngoing(at: now), !event.isAllDay {
                        Text("IN CORSO").font(.system(size: 8.5, weight: .bold)).padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Capsule().fill(Color(nsColor: event.color).opacity(0.2)))
                            .foregroundStyle(Color(nsColor: event.color))
                    }
                }
                Text(Self.timeRange(event, use24Hour: use24Hour) + " · " + event.calendarTitle)
                    .font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
                if let location = event.location {
                    Label(location, systemImage: "mappin.and.ellipse").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let notes = event.notes {
                    Text(notes).font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(2)
                }
                if let url = event.meetingURL, !past {
                    Button { NSWorkspace.shared.open(url) } label: { Label("Partecipa", systemImage: "video.fill").font(.system(size: 11)) }
                        .buttonStyle(.link)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(past ? 0.5 : 1)
        .contentShape(Rectangle())
    }

    static func timeRange(_ event: CalendarEvent, use24Hour: Bool) -> String {
        guard !event.isAllDay else { return "Tutto il giorno" }
        let pattern = use24Hour ? "HH:mm" : "h:mm a"
        return "\(DateText.string(event.start, pattern))–\(DateText.string(event.end, pattern))"
    }
}

/// Month grid (Monday first) with navigation and today highlighted; with a selection, days with events get a dot and
/// a click picks the day whose events are listed.
struct MonthCalendar: View {
    var calendar: Calendar
    @Binding var monthOffset: Int
    var selected: Binding<Date>? = nil
    var busyDays: Set<Date> = []

    var body: some View {
        let today = Date()
        let month = calendar.date(byAdding: .month, value: monthOffset, to: today) ?? today
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let cells: [Date?] = Array(repeating: nil, count: leading)
            + (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let rows = Int(ceil(Double(cells.count) / 7))

        VStack(spacing: 6) {
            HStack {
                Text(DateText.string(start, "MMMM yyyy").capitalized(with: Locale(identifier: "it_IT")))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if monthOffset != 0 || !(selected.map { calendar.isDateInToday($0.wrappedValue) } ?? true) {
                    Button("Oggi") {
                        monthOffset = 0
                        selected?.wrappedValue = Date()
                    }.buttonStyle(.link).font(.system(size: 11))
                }
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
            }
            HStack(spacing: 0) {
                ForEach(Array(["L", "M", "M", "G", "V", "S", "D"].enumerated()), id: \.offset) { index, name in
                    Text(name).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(index >= 5 ? Color.secondary.opacity(0.7) : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let index = row * 7 + column
                        let date = index < cells.count ? cells[index] : nil
                        dayCell(date, weekend: column >= 5, today: today)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder private func dayCell(_ date: Date?, weekend: Bool, today: Date) -> some View {
        if let date {
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let isSelected = selected.map { calendar.isDate(date, inSameDayAs: $0.wrappedValue) } ?? false
            let busy = busyDays.contains(calendar.startOfDay(for: date))
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12, weight: isToday || isSelected ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : (weekend ? Color.secondary : Color.primary))
                    .frame(width: 26, height: 22)
                    .background(Circle().fill(isToday ? Palette.color(0) : Color.clear))
                    .overlay(Circle().strokeBorder(isSelected && !isToday ? Palette.color(0) : Color.clear, lineWidth: 1.5))
                Circle().fill(busy ? Palette.color(1) : Color.clear).frame(width: 4, height: 4)
            }
            .frame(height: selected == nil ? 24 : 28)
            .contentShape(Rectangle())
            .onTapGesture { selected?.wrappedValue = date }
        } else {
            Color.clear.frame(width: 26, height: selected == nil ? 24 : 28)
        }
    }
}

// MARK: - Weather

struct WeatherTab: View {
    @ObservedObject var weather: WeatherService
    @ObservedObject private var settings = Settings.shared
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if weather.report == nil, settings.weatherLocation == nil {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Scegli una città", systemImage: "location.magnifyingglass").font(.system(size: 13, weight: .semibold))
                        Text("Imposta la città in Impostazioni ▸ Meteo: MenuStats manda a Open-Meteo solo le sue coordinate.")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Apri Impostazioni…", action: openSettings)
                    }
                }
            } else if let report = weather.report {
                WeatherHero(report: report)
                HourlyStrip(hours: report.hours, use24Hour: settings.use24Hour)
                DailyForecast(days: report.days)
                HStack {
                    Text("Aggiornato alle \(DateText.string(report.updated, "HH:mm")) · Dati Open-Meteo")
                    Spacer()
                    Button { weather.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).help("Aggiorna")
                }
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
            } else if let error = weather.error {
                Card {
                    Label(error, systemImage: "wifi.exclamationmark").font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Riprova") { weather.refresh() }
                }
            } else {
                Card {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Caricamento del meteo…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                }
            }
        }
    }
}

/// Current conditions on a sky gradient that follows the weather and time of day.
struct WeatherHero: View {
    var report: WeatherReport

    private var sky: [Color] {
        let code = report.code
        if !report.isDay {
            return code >= 51 ? [Color(red: 0.13, green: 0.16, blue: 0.27), Color(red: 0.06, green: 0.07, blue: 0.13)]
                              : [Color(red: 0.11, green: 0.15, blue: 0.36), Color(red: 0.03, green: 0.05, blue: 0.15)]
        }
        switch code {
        case 0, 1: return [Color(red: 0.24, green: 0.55, blue: 0.93), Color(red: 0.52, green: 0.77, blue: 0.98)]
        case 2: return [Color(red: 0.33, green: 0.55, blue: 0.82), Color(red: 0.62, green: 0.75, blue: 0.88)]
        case 3, 45, 48: return [Color(red: 0.45, green: 0.52, blue: 0.60), Color(red: 0.66, green: 0.71, blue: 0.77)]
        case 71...86: return [Color(red: 0.55, green: 0.65, blue: 0.76), Color(red: 0.80, green: 0.86, blue: 0.92)]
        case 95...99: return [Color(red: 0.22, green: 0.24, blue: 0.33), Color(red: 0.40, green: 0.42, blue: 0.52)]
        default: return [Color(red: 0.30, green: 0.40, blue: 0.53), Color(red: 0.50, green: 0.58, blue: 0.68)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Label(report.location.name, systemImage: "location.fill")
                        .font(.system(size: 13, weight: .semibold)).labelStyle(.titleAndIcon)
                    Text(Format.temperature(report.temperature, unit: false))
                        .font(.system(size: 52, weight: .thin, design: .rounded)).monospacedDigit()
                    Text(report.condition.description).font(.system(size: 13, weight: .medium))
                    if let today = report.today {
                        Text("Max \(Format.temperature(today.maximum, unit: false))  Min \(Format.temperature(today.minimum, unit: false))")
                            .font(.system(size: 12)).opacity(0.85).monospacedDigit()
                    }
                }
                Spacer()
                Image(systemName: report.condition.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 54))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    .padding(.top, 8)
            }
            HStack(spacing: 0) {
                if let apparent = report.apparentTemperature { detail("thermometer.medium", "Percepita", Format.temperature(apparent, unit: false)) }
                if let humidity = report.humidity { detail("humidity.fill", "Umidità", "\(humidity)%") }
                if let wind = report.windSpeed { detail("wind", "Vento", String(format: "%.0f km/h", wind)) }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: sky, startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    private func detail(_ symbol: String, _ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol).font(.system(size: 10.5)).opacity(0.8)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HourlyStrip: View {
    var hours: [WeatherReport.Hour]
    var use24Hour: Bool

    var body: some View {
        Card(title: "Prossime ore") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                        VStack(spacing: 5) {
                            Text(index == 0 ? "Ora" : DateText.string(hour.date, use24Hour ? "HH" : "h a"))
                                .font(.system(size: 11, weight: index == 0 ? .semibold : .regular)).foregroundStyle(.secondary)
                            Image(systemName: WeatherCondition(code: hour.code, isDay: hour.isDay).symbol)
                                .symbolRenderingMode(.multicolor).font(.system(size: 17)).frame(height: 20)
                                .weatherSymbolContrast()
                            if let chance = hour.precipitationChance, chance >= 20 {
                                Text("\(chance)%").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Palette.color(0))
                            } else {
                                Text(" ").font(.system(size: 9.5))
                            }
                            Text(Format.temperature(hour.temperature, unit: false)).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                        }
                        .frame(minWidth: 30)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// Seven days with an iOS-style range bar: each day's min…max placed on the week's overall range.
struct DailyForecast: View {
    var days: [WeatherReport.Day]

    var body: some View {
        let low = days.map(\.minimum).min() ?? 0
        let high = days.map(\.maximum).max() ?? 1
        Card(title: "Prossimi 7 giorni") {
            VStack(spacing: 7) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    HStack(spacing: 8) {
                        Text(index == 0 ? "Oggi" : DateText.string(day.date, "EEE").capitalized(with: Locale(identifier: "it_IT")))
                            .font(.system(size: 12.5, weight: index == 0 ? .semibold : .regular))
                            .frame(width: 38, alignment: .leading)
                        Image(systemName: WeatherCondition(code: day.code, isDay: true).symbol)
                            .symbolRenderingMode(.multicolor).font(.system(size: 15)).frame(width: 22)
                            .weatherSymbolContrast()
                        Text((day.precipitationChance ?? 0) >= 20 ? "\(day.precipitationChance!)%" : "")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.color(0))
                            .frame(width: 30, alignment: .leading)
                        Text(Format.temperature(day.minimum, unit: false)).font(.system(size: 12.5)).foregroundStyle(.secondary)
                            .monospacedDigit().frame(width: 32, alignment: .trailing)
                        RangeBar(low: low, high: high, minimum: day.minimum, maximum: day.maximum)
                        Text(Format.temperature(day.maximum, unit: false)).font(.system(size: 12.5, weight: .semibold))
                            .monospacedDigit().frame(width: 32, alignment: .leading)
                    }
                }
            }
        }
    }
}

struct RangeBar: View {
    var low: Double, high: Double, minimum: Double, maximum: Double

    var body: some View {
        GeometryReader { geometry in
            let span = max(high - low, 1)
            let start = CGFloat((minimum - low) / span) * geometry.size.width
            let end = CGFloat((maximum - low) / span) * geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.neutral)
                Capsule()
                    .fill(LinearGradient(colors: [Self.color(minimum), Self.color(maximum)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(end - start, 6))
                    .offset(x: start)
            }
        }
        .frame(height: 5)
    }

    /// Temperature → color: cold blue, mild green, warm yellow/orange, hot red.
    static func color(_ celsius: Double) -> Color {
        switch celsius {
        case ..<5: Color(red: 0.35, green: 0.60, blue: 0.98)
        case ..<12: Color(red: 0.30, green: 0.78, blue: 0.85)
        case ..<18: Color(red: 0.42, green: 0.80, blue: 0.45)
        case ..<24: Color(red: 0.98, green: 0.80, blue: 0.25)
        case ..<30: Color(red: 0.98, green: 0.58, blue: 0.20)
        default: Color(red: 0.93, green: 0.30, blue: 0.25)
        }
    }
}

extension View {
    /// Multicolor weather symbols draw clouds in white: a soft shadow keeps them visible on light backgrounds.
    func weatherSymbolContrast() -> some View {
        shadow(color: .black.opacity(0.28), radius: 1.2, x: 0, y: 0.6)
    }
}
