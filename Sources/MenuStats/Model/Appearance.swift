import AppKit
import Combine

/// Applies the chosen look (Normale, Chiara, Scura, Automatica) to MenuStats' own windows: the dropdown and Settings.
/// The status items are left alone, so the menu bar icons keep matching the real menu bar.
final class AppearanceController {
    private let settings: Settings
    private let weather: WeatherService
    private var cancellables: Set<AnyCancellable> = []
    private var timer: Timer?

    init(settings: Settings, weather: WeatherService) {
        self.settings = settings
        self.weather = weather
        settings.$appearanceMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.apply() } }
            .store(in: &cancellables)
        // Automatic mode switches at sunrise and sunset: a check a minute is plenty.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.apply() }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The appearance MenuStats' windows should use now; nil follows macOS.
    var current: NSAppearance? {
        switch settings.appearanceMode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .automatic: NSAppearance(named: Self.isNight(at: Date(), today: weather.report?.today) ? .darkAqua : .aqua)
        }
    }

    /// Dark from sunset to sunrise (from the Weather module when it knows them), otherwise from 20:00 to 7:00.
    static func isNight(at date: Date, today: WeatherReport.Day?) -> Bool {
        if let sunrise = today?.sunrise, let sunset = today?.sunset, Calendar.current.isDate(sunrise, inSameDayAs: date) {
            return date < sunrise || date >= sunset
        }
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 20 || hour < 7
    }

    /// What "Alba e tramonto" does today, for Settings: "Scura dalle 17:02 alle 7:05 (alba e tramonto di Roma)".
    static func scheduleDescription(today: WeatherReport.Day?, now: Date) -> String {
        let night = isNight(at: now, today: today) ? "Ora è scura" : "Ora è chiara"
        if let sunrise = today?.sunrise, let sunset = today?.sunset, Calendar.current.isDate(sunrise, inSameDayAs: now) {
            let format = DateFormatter()
            format.dateFormat = "HH:mm"
            return "\(night): scura dal tramonto (\(format.string(from: sunset))) all'alba (\(format.string(from: sunrise))), orari del Meteo."
        }
        return "\(night): scura dalle 20:00 alle 7:00 (accendi il Meteo per usare alba e tramonto veri)."
    }

    func apply() {
        let appearance = current
        for window in NSApp.windows where !Self.isStatusBarWindow(window) {
            if window.appearance != appearance { window.appearance = appearance }
        }
    }

    private static func isStatusBarWindow(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("StatusBar")
    }
}
