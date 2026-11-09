import AppKit
import SwiftUI
import Combine
import Foundation

enum ModuleID: String, CaseIterable, Identifiable, Codable {
    case cpu, memory, disk, network, sensors, fans, battery, weather, date, awake
    var id: String { rawValue }

    /// Modules this Mac has hardware for: no Fans on a fanless MacBook Air, no Battery on a desktop.
    var isAvailable: Bool {
        switch self {
        case .fans: HardwarePresence.hasFans
        case .battery: HardwarePresence.hasBattery
        default: true
        }
    }

    static var available: [ModuleID] { allCases.filter(\.isAvailable) }

    var name: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memoria"
        case .disk: "Disco"
        case .network: "Rete"
        case .sensors: "Temperature"
        case .fans: "Ventole"
        case .battery: "Batteria"
        case .weather: "Meteo"
        case .date: "Data e ora"
        case .awake: "Sveglio"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .sensors: "thermometer.medium"
        case .fans: "fan"
        case .battery: "battery.75percent"
        case .weather: "cloud.sun"
        case .date: "calendar"
        case .awake: "cup.and.saucer"
        }
    }

    /// The dashboard tab opened by clicking this module.
    var tab: DashboardTab {
        switch self {
        case .cpu: .cpu
        case .memory: .memory
        case .disk: .disk
        case .network: .network
        case .sensors, .fans: .sensors
        case .battery: .battery
        case .weather: .weather
        case .date: .date
        case .awake: .awake
        }
    }
}

enum DashboardTab: String, CaseIterable, Identifiable {
    case cpu, memory, disk, network, sensors, battery, weather, date, awake, map
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memoria"
        case .disk: "Disco"
        case .network: "Rete"
        case .sensors: "Sensori"
        case .battery: "Batteria"
        case .weather: "Meteo"
        case .date: "Data"
        case .awake: "Sveglio"
        case .map: "Mappa"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .sensors: "thermometer.medium"
        case .battery: "battery.75percent"
        case .weather: "cloud.sun"
        case .date: "calendar"
        case .awake: "cup.and.saucer"
        case .map: "map"
        }
    }

    /// The palette role of the tab's main color (its icon in the dropdown's tab bar, the map pin).
    var primaryColorIndex: Int {
        switch self {
        case .battery: 2
        case .awake: 3
        case .map: 4
        default: 0
        }
    }

    /// Every color the tab draws with, by palette role, as Settings lists them. A role is a slot of the palette:
    /// all the tab's elements with that role change together.
    var colorRoles: [(index: Int, name: String)] {
        switch self {
        case .cpu: [(0, "Utente e core prestazioni"), (1, "Sistema"), (2, "Core efficienza"), (3, "GPU")]
        case .memory: [(0, "App e memoria usata"), (1, "Wired e swap"), (2, "Compressa"), (3, "Cache")]
        case .disk: [(0, "Lettura e spazio usato"), (1, "Scrittura"), (3, "Eliminabile")]
        case .network: [(0, "Download"), (1, "Upload")]
        case .sensors: [(0, "CPU"), (1, "SSD e mappa del calore"), (2, "Ventole"), (3, "Consumo")]
        case .battery: [(2, "Carica e dispositivi"), (3, "Potenza e app")]
        case .weather: [(0, "Accento")]
        case .date: [(0, "Oggi e prossimo impegno"), (1, "Giorni con impegni")]
        case .awake: [(3, "Sessione attiva")]
        case .map: [(4, "Questo Mac"), (0, "Dispositivi vicini"), (2, "Dispositivi collegati")]
        }
    }

    /// Network and disk share their two main colors with the menu bar graphs: one setting, the same color everywhere.
    func graphSeries(role: Int) -> GraphSeries? {
        switch (self, role) {
        case (.network, 0): .download
        case (.network, 1): .upload
        case (.disk, 0): .read
        case (.disk, 1): .write
        default: nil
        }
    }

    /// Optional tabs only appear while their module is enabled.
    var isOptional: Bool { self == .weather || self == .date || self == .awake }
}

/// Optional sections of the dropdown. A hidden section is also not measured (no process list, no nettop,
/// no full sensor scan…), so hiding what you don't use makes MenuStats lighter.
enum PanelSection: String, CaseIterable, Identifiable, Codable {
    case cpuChart, cpuCores, cpuLoad, cpuProcesses
    case memoryComposition, memoryCharts, memoryProcesses
    case diskVolumes, diskChart, diskProcesses
    case networkChart, networkConnection, networkPublic, networkApps
    case sensorsChart, sensorsFans, sensorsGrid
    case batteryCharts, batteryApps, batteryHealth, batteryPower, batteryControls

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuChart: "Grafico utilizzo"
        case .cpuCores: "Core"
        case .cpuLoad: "Carico"
        case .cpuProcesses: "Processi"
        case .memoryComposition: "Composizione"
        case .memoryCharts: "Grafici memoria e swap"
        case .memoryProcesses: "Processi"
        case .diskVolumes: "Volumi"
        case .diskChart: "Grafico attività"
        case .diskProcesses: "Processi"
        case .networkChart: "Grafico traffico"
        case .networkConnection: "Connessione"
        case .networkPublic: "IP pubblico e VPN"
        case .networkApps: "App (download + upload)"
        case .sensorsChart: "Grafico temperature"
        case .sensorsFans: "Ventole e alimentazione"
        case .sensorsGrid: "Elenco sensori"
        case .batteryCharts: "Grafici carica e potenza"
        case .batteryApps: "App che consumano di più"
        case .batteryHealth: "Salute"
        case .batteryPower: "Alimentazione"
        case .batteryControls: "Controlli"
        }
    }

    /// What hiding it saves, shown in Settings.
    var saving: String? {
        switch self {
        case .cpuProcesses, .memoryProcesses, .diskProcesses, .batteryApps: "non elenca i processi"
        case .networkApps: "non avvia nettop"
        case .networkPublic: "non cerca l'IP pubblico né la VPN"
        case .sensorsGrid: "non legge tutti i sensori né la GPU"
        case .diskVolumes: "non calcola lo spazio eliminabile"
        case .sensorsFans: "legge ventole e consumo più di rado"
        default: nil
        }
    }

    var tab: DashboardTab {
        switch self {
        case .cpuChart, .cpuCores, .cpuLoad, .cpuProcesses: .cpu
        case .memoryComposition, .memoryCharts, .memoryProcesses: .memory
        case .diskVolumes, .diskChart, .diskProcesses: .disk
        case .networkChart, .networkConnection, .networkPublic, .networkApps: .network
        case .sensorsChart, .sensorsFans, .sensorsGrid: .sensors
        case .batteryCharts, .batteryApps, .batteryHealth, .batteryPower, .batteryControls: .battery
        }
    }

    /// The settings page that lists it.
    var module: ModuleID {
        switch tab {
        case .cpu: .cpu
        case .memory: .memory
        case .disk: .disk
        case .network: .network
        case .sensors: self == .sensorsFans ? .fans : .sensors
        case .battery: .battery
        case .weather, .map: .weather // no section lives in the Map tab
        case .date: .date
        case .awake: .awake
        }
    }
}

// MARK: - Per-module menu bar styles

protocol StyleOption: RawRepresentable, CaseIterable, Identifiable, Hashable where RawValue == String {
    var label: String { get }
}

extension StyleOption {
    var id: String { rawValue }
}

enum CPUStyle: String, StyleOption {
    case graphPercent, percent, graph, cores
    var label: String { ["Grafico e percentuale", "Percentuale", "Grafico", "Barre per core"][Self.allCases.firstIndex(of: self)!] }
}

enum MemoryStyle: String, StyleOption {
    case ringPercent, percent, used, pressure
    var label: String { ["Anello e percentuale", "Percentuale", "Memoria usata", "Pressione"][Self.allCases.firstIndex(of: self)!] }
}

enum DiskStyle: String, StyleOption {
    case activity, free, usedPercent, graphs, graphsValues
    var label: String {
        ["Lettura e scrittura", "Spazio libero", "Spazio usato (%)", "Grafici scrittura e lettura", "Grafici e valori"][Self.allCases.firstIndex(of: self)!]
    }
    var usesGraphs: Bool { self == .graphs || self == .graphsValues }
}

enum NetworkStyle: String, StyleOption {
    case stacked, download, total, graphs, graphsValues
    var label: String {
        ["Upload e download", "Solo download", "Totale", "Grafici upload e download", "Grafici e valori"][Self.allCases.firstIndex(of: self)!]
    }
    var usesGraphs: Bool { self == .graphs || self == .graphsValues }
}

/// The two halves of the network and disk graphs, each with its own color.
enum GraphSeries: String, CaseIterable, Identifiable {
    case upload, download, write, read
    var id: String { rawValue }
    var label: String { ["Upload", "Download", "Scrittura", "Lettura"][Self.allCases.firstIndex(of: self)!] }
    static let defaultColors: [GraphSeries: String] = [
        .upload: "#EB6834", .download: "#2A78D6", .write: "#D55181", .read: "#1BAF7A",
    ]
}

enum SensorSource: String, StyleOption {
    case cpuAverage, cpuMax, hottest, ssd, battery
    var label: String { ["CPU (media dei core)", "CPU (core più caldo)", "Sensore più caldo", "SSD", "Batteria"][Self.allCases.firstIndex(of: self)!] }
}

enum FanStyle: String, StyleOption {
    case rpm, percent, iconOnly
    var label: String { ["Giri al minuto", "Percentuale del massimo", "Solo icona"][Self.allCases.firstIndex(of: self)!] }
}

enum BatteryStyle: String, StyleOption {
    case percent, time, percentTime, watts, iconOnly, insidePercent
    var label: String { ["Percentuale", "Tempo rimanente", "Percentuale e tempo rimanente", "Potenza (W)", "Solo icona", "Percentuale nell'icona"][Self.allCases.firstIndex(of: self)!] }
}

enum DateStyle: String, StyleOption {
    case dayTime, time, timeSeconds, stacked, shortDate, numeric, long, calendarIcon, calendarIconTime
    var label: String {
        ["Giorno e ora", "Solo ora", "Ora con secondi", "Data sopra l'ora", "Data breve", "Data numerica", "Data estesa",
         "Icona calendario e mese", "Icona calendario, mese e ora"][Self.allCases.firstIndex(of: self)!]
    }
}

enum WeatherStyle: String, StyleOption {
    case iconTemperature, temperature, iconOnly, stacked
    var label: String { ["Icona e temperatura", "Solo temperatura", "Solo icona", "Città sopra la temperatura"][Self.allCases.firstIndex(of: self)!] }
}

enum AwakeStyle: String, StyleOption {
    case icon, iconTime, stacked
    var label: String { ["Solo icona", "Icona e tempo rimanente", "Stato sopra il tempo"][Self.allCases.firstIndex(of: self)!] }
}

/// Whether the weather place is typed by hand or found from the Mac's position.
enum WeatherLocationMode: String, StyleOption {
    case manual, automatic
    var label: String { ["Manuale", "Automatica"][Self.allCases.firstIndex(of: self)!] }
}

/// The place the weather is shown for (chosen in Settings; only its coordinates are sent to Open-Meteo).
struct WeatherLocation: Codable, Equatable, Identifiable {
    var name: String
    var region: String?
    var country: String?
    var latitude: Double
    var longitude: Double

    var id: String { "\(latitude),\(longitude)" }
    var detail: String { [region, country].compactMap { $0 }.joined(separator: ", ") }
}

enum MenubarLayout: String, StyleOption {
    case combined, separate
    var label: String { ["Una voce unica (compatta)", "Una voce per modulo"][Self.allCases.firstIndex(of: self)!] }
}

/// When the fan icon spins in the menu bar. Each frame is a new image for macOS to show, 12 a second, which costs
/// battery (about 13 points of a core against 1); a still fan keeps its meaning.
enum IconAnimation: String, StyleOption {
    case always, onPower, never
    var label: String { ["Sempre", "Solo con l'alimentatore", "Mai"][Self.allCases.firstIndex(of: self)!] }

    /// Never in Low Power Mode; `onACPower` is nil on Macs without a battery, which always count as plugged in.
    func allowsMotion(lowPowerMode: Bool, onACPower: Bool?) -> Bool {
        guard !lowPowerMode else { return false }
        switch self {
        case .always: return true
        case .onPower: return onACPower ?? true
        case .never: return false
        }
    }
}

/// Look of MenuStats' own windows (dropdown and Settings). The menu bar keeps following macOS.
/// "Come macOS" follows System Settings ▸ Appearance (itself light, dark or automatic); "Alba e tramonto" is
/// MenuStats' own schedule: dark from sunset to sunrise of the Weather city (20:00–7:00 without Weather).
enum AppearanceMode: String, StyleOption {
    case system, light, dark, automatic
    var label: String { ["Come macOS", "Chiara", "Scura", "Alba e tramonto"][Self.allCases.firstIndex(of: self)!] }
    var symbol: String { ["circle.lefthalf.filled", "sun.max", "moon", "clock"][Self.allCases.firstIndex(of: self)!] }
}

/// The dropdown's background: macOS's translucent material, or a solid color that keeps text readable on any
/// wallpaper or window behind it.
enum PanelBackground: String, StyleOption {
    case solid, translucent
    var label: String { ["Pieno", "Trasparente"][Self.allCases.firstIndex(of: self)!] }
}

enum TemperatureUnit: String, StyleOption {
    case celsius, fahrenheit
    var label: String { ["Celsius (°C)", "Fahrenheit (°F)"][Self.allCases.firstIndex(of: self)!] }
}

// MARK: - Settings store

/// All user preferences, persisted in UserDefaults. Views bind to it; the menu bar re-renders on change.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    // General
    @Published var layout: MenubarLayout { didSet { save(layout.rawValue, "layout") } }
    @Published var refreshInterval: Double { didSet { save(refreshInterval, "refreshInterval") } }
    @Published var temperatureUnit: TemperatureUnit { didSet { save(temperatureUnit.rawValue, "temperatureUnit"); Format.fahrenheit = temperatureUnit == .fahrenheit } }
    @Published var showLabels: Bool { didSet { save(showLabels, "showLabels") } }
    @Published var dynamicIcons: Bool { didSet { save(dynamicIcons, "dynamicIcons") } }
    @Published var iconAnimation: IconAnimation { didSet { save(iconAnimation.rawValue, "iconAnimation") } }
    /// Yellow → orange → red when a module needs attention (on by default; icons stay monochrome otherwise).
    @Published var severityColors: Bool { didSet { save(severityColors, "severityColors") } }
    /// Optional: tint each module's icon with a color of the user's choice.
    @Published var colorIcons: Bool { didSet { save(colorIcons, "colorIcons") } }
    @Published var moduleColors: [ModuleID: String] {
        didSet { save(Dictionary(uniqueKeysWithValues: moduleColors.map { ($0.key.rawValue, $0.value) }), "moduleColors") }
    }
    @Published var processCount: Int { didSet { save(processCount, "processCount") } }
    @Published var groupProcessesByApp: Bool { didSet { save(groupProcessesByApp, "groupProcessesByApp") } }
    @Published var publicIPEnabled: Bool { didSet { save(publicIPEnabled, "publicIPEnabled") } }
    @Published var showVPNCountry: Bool { didSet { save(showVPNCountry, "showVPNCountry") } }
    @Published var showIPv6: Bool { didSet { save(showIPv6, "showIPv6") } }
    @Published var showCountryFlag: Bool { didSet { save(showCountryFlag, "showCountryFlag") } }
    @Published var showVPN: Bool { didSet { save(showVPN, "showVPN") } }
    @Published var hiddenSections: Set<PanelSection> { didSet { save(hiddenSections.map(\.rawValue), "hiddenSections") } }
    @Published var appearanceMode: AppearanceMode { didSet { save(appearanceMode.rawValue, "appearanceMode") } }
    @Published var panelBackground: PanelBackground { didSet { save(panelBackground.rawValue, "panelBackground") } }
    /// The color preset chosen in Settings ▸ Generali (nil: none chosen yet, the built-in colors).
    @Published var colorPreset: String? {
        didSet { if let colorPreset { save(colorPreset, "colorPreset") } else { defaults.removeObject(forKey: "colorPreset") } }
    }
    /// `colorFingerprint` right after applying the preset, to tell when a color was edited afterwards.
    @Published var colorPresetFingerprint: String { didSet { save(colorPresetFingerprint, "colorPresetFingerprint") } }
    /// Menu bar values take only the width they need now (off: the widest they can get, so nothing ever moves).
    @Published var menubarDynamicWidth: Bool { didSet { save(menubarDynamicWidth, "menubarDynamicWidth") } }
    /// Points between two modules in the single menu bar item.
    @Published var menubarSpacing: Double { didSet { save(menubarSpacing, "menubarSpacing") } }
    /// Dropdown colors picked in Settings, per tab and palette role (see `DashboardTab.colorRoles`); a missing entry
    /// keeps the built-in palette. Network and disk keep their two main colors in `graphSeriesColors` instead.
    @Published var panelColors: [DashboardTab: [Int: String]] {
        didSet {
            save(Dictionary(uniqueKeysWithValues: panelColors.map { tab, roles in
                (tab.rawValue, Dictionary(uniqueKeysWithValues: roles.map { (String($0.key), $0.value) }))
            }), "panelColors")
        }
    }
    /// Narrow menu bar (no labels, only the first modules), so macOS 27 is less likely to hide it next to the notch.
    @Published var compactMenubar: Bool { didSet { save(compactMenubar, "compactMenubar") } }
    @Published var compactModuleCount: Int { didSet { save(compactModuleCount, "compactModuleCount") } }
    /// Keeps MenuStats next to the clock, so other apps' icons are the ones macOS hides when the bar is full.
    @Published var pinNearClock: Bool { didSet { save(pinNearClock, "pinNearClock") } }
    /// When macOS hides MenuStats anyway (notch, full bar), drops labels and then the last modules until it fits.
    @Published var autoFitMenubar: Bool { didSet { save(autoFitMenubar, "autoFitMenubar") } }

    // Menu bar modules
    @Published var moduleOrder: [ModuleID] { didSet { save(moduleOrder.map(\.rawValue), "moduleOrder") } }
    @Published var enabledModules: Set<ModuleID> { didSet { save(enabledModules.map(\.rawValue), "enabledModules") } }

    // Styles
    @Published var cpuStyle: CPUStyle { didSet { save(cpuStyle.rawValue, "cpuStyle") } }
    @Published var memoryStyle: MemoryStyle { didSet { save(memoryStyle.rawValue, "memoryStyle") } }
    @Published var diskStyle: DiskStyle { didSet { save(diskStyle.rawValue, "diskStyle") } }
    @Published var networkStyle: NetworkStyle { didSet { save(networkStyle.rawValue, "networkStyle") } }
    /// Network and disk graphs in their own two colors (off: the module's color, monochrome by default).
    @Published var graphColors: Bool { didSet { save(graphColors, "graphColors") } }

    // Calendar
    /// Events from the Mac's calendars in the Date tab (access is asked at launch).
    @Published var calendarEvents: Bool { didSet { save(calendarEvents, "calendarEvents") } }
    @Published var hiddenCalendars: Set<String> { didSet { save(Array(hiddenCalendars), "hiddenCalendars") } }
    /// While a macOS Focus with a Calendar filter is on, show only the calendars it lets through.
    @Published var calendarFollowFocus: Bool { didSet { save(calendarFollowFocus, "calendarFollowFocus") } }
    /// The menu bar steps aside to announce an event shortly before it starts.
    @Published var calendarAlerts: Bool { didSet { save(calendarAlerts, "calendarAlerts") } }
    @Published var calendarAlertMinutes: Int { didSet { save(calendarAlertMinutes, "calendarAlertMinutes") } }
    @Published var calendarAlertSeconds: Int { didSet { save(calendarAlertSeconds, "calendarAlertSeconds") } }
    @Published var calendarAlertRepeats: Int { didSet { save(calendarAlertRepeats, "calendarAlertRepeats") } }
    @Published var calendarAlertRepeatMinutes: Int { didSet { save(calendarAlertRepeatMinutes, "calendarAlertRepeatMinutes") } }
    @Published var calendarAlertAtStart: Bool { didSet { save(calendarAlertAtStart, "calendarAlertAtStart") } }
    @Published var graphSeriesColors: [GraphSeries: String] {
        didSet { save(Dictionary(uniqueKeysWithValues: graphSeriesColors.map { ($0.key.rawValue, $0.value) }), "graphSeriesColors") }
    }
    @Published var sensorSource: SensorSource { didSet { save(sensorSource.rawValue, "sensorSource") } }
    @Published var fanStyle: FanStyle { didSet { save(fanStyle.rawValue, "fanStyle") } }
    @Published var batteryStyle: BatteryStyle { didSet { save(batteryStyle.rawValue, "batteryStyle") } }
    @Published var dateStyle: DateStyle { didSet { save(dateStyle.rawValue, "dateStyle") } }
    @Published var use24Hour: Bool { didSet { save(use24Hour, "use24Hour") } }
    @Published var weatherStyle: WeatherStyle { didSet { save(weatherStyle.rawValue, "weatherStyle") } }
    @Published var awakeStyle: AwakeStyle { didSet { save(awakeStyle.rawValue, "awakeStyle") } }
    /// Awake sessions keep the Mac running but let the screen turn off.
    @Published var awakeAllowDisplaySleep: Bool { didSet { save(awakeAllowDisplaySleep, "awakeAllowDisplaySleep") } }
    /// Also stay awake with the lid closed (through the root helper), while a session runs.
    @Published var awakeLidClosed: Bool { didSet { save(awakeLidClosed, "awakeLidClosed") } }
    @Published var awakeEndOnLowBattery: Bool { didSet { save(awakeEndOnLowBattery, "awakeEndOnLowBattery") } }
    @Published var awakeLowBatteryThreshold: Double { didSet { save(awakeLowBatteryThreshold, "awakeLowBatteryThreshold") } }
    /// Last custom duration, in minutes, and how long a download may stay still before it counts as finished (seconds).
    @Published var awakeCustomMinutes: Int { didSet { save(awakeCustomMinutes, "awakeCustomMinutes") } }
    @Published var awakeDownloadTimeout: Int { didSet { save(awakeDownloadTimeout, "awakeDownloadTimeout") } }
    /// Stay awake while an AI tool reports (through files in ~/.menustats/ai) that it is working.
    @Published var awakeWatchAI: Bool { didSet { save(awakeWatchAI, "awakeWatchAI") } }
    @Published var awakeAIAllowDisplaySleep: Bool { didSet { save(awakeAIAllowDisplaySleep, "awakeAIAllowDisplaySleep") } }
    /// A signal not refreshed for this long (minutes) is ignored, e.g. after an interrupted run that never reported its end.
    @Published var awakeAIStaleMinutes: Int { didSet { save(awakeAIStaleMinutes, "awakeAIStaleMinutes") } }
    /// Minutes without any AI activity before an AI session ends.
    @Published var awakeAIGraceMinutes: Int { didSet { save(awakeAIGraceMinutes, "awakeAIGraceMinutes") } }

    // Nearby devices (Map tab)
    /// The radar drawing in the Map tab's nearby-devices card; the list below it is always shown.
    @Published var nearbyShowRadar: Bool { didSet { save(nearbyShowRadar, "nearbyShowRadar") } }
    /// Lock the Mac when the chosen devices move away. Always on while enabled, whatever tab is open.
    @Published var proximityLockEnabled: Bool { didSet { save(proximityLockEnabled, "proximityLockEnabled") } }
    /// The devices to watch: Bluetooth address → name (the name is only kept to show it).
    @Published var proximityLockDevices: [String: String] { didSet { save(proximityLockDevices, "proximityLockDevices") } }
    /// How the chosen devices count: lock when any one of them is away, or only when all of them are.
    @Published var proximityLockRequiresAll: Bool { didSet { save(proximityLockRequiresAll, "proximityLockRequiresAll") } }
    /// Seconds a device must stay out of range before the Mac locks.
    @Published var proximityLockGrace: Int { didSet { save(proximityLockGrace, "proximityLockGrace") } }
    /// Also count a device as away when it is farther than `proximityLockDistance` meters (estimated from the signal).
    @Published var proximityLockUseDistance: Bool { didSet { save(proximityLockUseDistance, "proximityLockUseDistance") } }
    @Published var proximityLockDistance: Double { didSet { save(proximityLockDistance, "proximityLockDistance") } }
    @Published var weatherLocationMode: WeatherLocationMode { didSet { save(weatherLocationMode.rawValue, "weatherLocationMode") } }
    @Published var weatherLocation: WeatherLocation? {
        didSet {
            if let weatherLocation, let data = try? JSONEncoder().encode(weatherLocation) {
                save(data, "weatherLocation")
            } else {
                defaults.removeObject(forKey: "weatherLocation")
            }
        }
    }

    // Dynamic icon thresholds
    @Published var cpuBusyThreshold: Double { didSet { save(cpuBusyThreshold, "cpuBusyThreshold") } }
    @Published var temperatureHotThreshold: Double { didSet { save(temperatureHotThreshold, "temperatureHotThreshold") } }

    // Notifications
    @Published var alertCPU: Bool { didSet { save(alertCPU, "alertCPU") } }
    @Published var alertCPUThreshold: Double { didSet { save(alertCPUThreshold, "alertCPUThreshold") } }
    @Published var alertTemperature: Bool { didSet { save(alertTemperature, "alertTemperature") } }
    @Published var alertTemperatureThreshold: Double { didSet { save(alertTemperatureThreshold, "alertTemperatureThreshold") } }
    @Published var alertBatteryLow: Bool { didSet { save(alertBatteryLow, "alertBatteryLow") } }
    @Published var alertBatteryLowThreshold: Double { didSet { save(alertBatteryLowThreshold, "alertBatteryLowThreshold") } }
    @Published var alertBatteryCharged: Bool { didSet { save(alertBatteryCharged, "alertBatteryCharged") } }
    @Published var alertBatteryChargedThreshold: Double { didSet { save(alertBatteryChargedThreshold, "alertBatteryChargedThreshold") } }
    @Published var alertFans: Bool { didSet { save(alertFans, "alertFans") } }
    @Published var alertAppCPU: Bool { didSet { save(alertAppCPU, "alertAppCPU") } }
    /// Fraction of one core, like Activity Monitor (1 = 100%).
    @Published var alertAppCPUThreshold: Double { didSet { save(alertAppCPUThreshold, "alertAppCPUThreshold") } }
    @Published var alertDiskLow: Bool { didSet { save(alertDiskLow, "alertDiskLow") } }
    @Published var alertDiskLowThreshold: Double { didSet { save(alertDiskLowThreshold, "alertDiskLowThreshold") } }
    @Published var alertNetworkDown: Bool { didSet { save(alertNetworkDown, "alertNetworkDown") } }

    private init() {
        let defaults = UserDefaults.standard
        func string<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        func double(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: key) as? Double ?? fallback }

        layout = string("layout", MenubarLayout.combined)
        refreshInterval = double("refreshInterval", 2)
        temperatureUnit = string("temperatureUnit", TemperatureUnit.celsius)
        showLabels = bool("showLabels", true)
        dynamicIcons = bool("dynamicIcons", true)
        iconAnimation = string("iconAnimation", IconAnimation.onPower)
        severityColors = bool("severityColors", true)
        colorIcons = bool("colorIcons", false)
        let savedColors = defaults.dictionary(forKey: "moduleColors") as? [String: String] ?? [:]
        moduleColors = Dictionary(uniqueKeysWithValues: ModuleID.allCases.map { module in
            (module, savedColors[module.rawValue] ?? Settings.defaultColors[module]!)
        })
        processCount = defaults.object(forKey: "processCount") as? Int ?? 5
        groupProcessesByApp = bool("groupProcessesByApp", true)
        publicIPEnabled = bool("publicIPEnabled", false)
        showIPv6 = bool("showIPv6", true)
        showVPNCountry = bool("showVPNCountry", true)
        showCountryFlag = bool("showCountryFlag", true)
        showVPN = bool("showVPN", true)
        hiddenSections = Set((defaults.stringArray(forKey: "hiddenSections") ?? []).compactMap(PanelSection.init(rawValue:)))
        appearanceMode = string("appearanceMode", AppearanceMode.system)
        panelBackground = string("panelBackground", PanelBackground.solid)
        menubarDynamicWidth = bool("menubarDynamicWidth", true)
        colorPreset = defaults.string(forKey: "colorPreset")
        colorPresetFingerprint = defaults.string(forKey: "colorPresetFingerprint") ?? ""
        menubarSpacing = double("menubarSpacing", 8)
        // Before 1.13 one color per tab ("tabColors") replaced only its main palette role.
        let legacyTabColors = (defaults.dictionary(forKey: "tabColors") as? [String: String] ?? [:])
            .compactMap { key, value in DashboardTab(rawValue: key).map { ($0, value) } }
        if let saved = defaults.dictionary(forKey: "panelColors") as? [String: [String: String]] {
            panelColors = Dictionary(uniqueKeysWithValues: saved.compactMap { key, roles in
                DashboardTab(rawValue: key).map { tab in (tab, Dictionary(uniqueKeysWithValues: roles.compactMap { role, hex in Int(role).map { ($0, hex) } })) }
            })
        } else {
            panelColors = Dictionary(uniqueKeysWithValues: legacyTabColors.filter { $0.0.graphSeries(role: $0.0.primaryColorIndex) == nil }
                .map { tab, hex in (tab, [tab.primaryColorIndex: hex]) })
        }
        compactMenubar = bool("compactMenubar", false)
        compactModuleCount = defaults.object(forKey: "compactModuleCount") as? Int ?? 3
        pinNearClock = bool("pinNearClock", true)
        autoFitMenubar = bool("autoFitMenubar", true)

        let savedOrder = (defaults.stringArray(forKey: "moduleOrder") ?? []).compactMap(ModuleID.init(rawValue:))
        moduleOrder = (savedOrder + ModuleID.allCases.filter { !savedOrder.contains($0) }).filter(\.isAvailable)
        enabledModules = Set((defaults.stringArray(forKey: "enabledModules")
            ?? ["cpu", "memory", "disk", "network", "sensors", "fans"]).compactMap(ModuleID.init(rawValue:)).filter(\.isAvailable))

        cpuStyle = string("cpuStyle", CPUStyle.graphPercent)
        memoryStyle = string("memoryStyle", MemoryStyle.ringPercent)
        diskStyle = string("diskStyle", DiskStyle.activity)
        networkStyle = string("networkStyle", NetworkStyle.stacked)
        graphColors = bool("graphColors", true)
        calendarEvents = bool("calendarEvents", true)
        hiddenCalendars = Set(defaults.stringArray(forKey: "hiddenCalendars") ?? [])
        calendarFollowFocus = bool("calendarFollowFocus", true)
        calendarAlerts = bool("calendarAlerts", true)
        calendarAlertMinutes = defaults.object(forKey: "calendarAlertMinutes") as? Int ?? 10
        calendarAlertSeconds = defaults.object(forKey: "calendarAlertSeconds") as? Int ?? 8
        calendarAlertRepeats = defaults.object(forKey: "calendarAlertRepeats") as? Int ?? 1
        calendarAlertRepeatMinutes = defaults.object(forKey: "calendarAlertRepeatMinutes") as? Int ?? 2
        calendarAlertAtStart = bool("calendarAlertAtStart", true)
        let savedGraphColors = defaults.dictionary(forKey: "graphSeriesColors") as? [String: String] ?? [:]
        var graphSeries = Dictionary(uniqueKeysWithValues: GraphSeries.allCases.map { series in
            (series, savedGraphColors[series.rawValue] ?? GraphSeries.defaultColors[series]!)
        })
        if defaults.object(forKey: "panelColors") == nil {
            for (tab, hex) in legacyTabColors { if let series = tab.graphSeries(role: tab.primaryColorIndex) { graphSeries[series] = hex } }
        }
        graphSeriesColors = graphSeries
        sensorSource = string("sensorSource", SensorSource.cpuAverage)
        fanStyle = string("fanStyle", FanStyle.rpm)
        batteryStyle = string("batteryStyle", BatteryStyle.percent)
        dateStyle = string("dateStyle", DateStyle.dayTime)
        use24Hour = bool("use24Hour", true)
        weatherStyle = string("weatherStyle", WeatherStyle.iconTemperature)
        awakeStyle = string("awakeStyle", AwakeStyle.iconTime)
        awakeAllowDisplaySleep = bool("awakeAllowDisplaySleep", false)
        awakeLidClosed = bool("awakeLidClosed", false)
        awakeEndOnLowBattery = bool("awakeEndOnLowBattery", true)
        awakeLowBatteryThreshold = double("awakeLowBatteryThreshold", 0.2)
        awakeCustomMinutes = defaults.object(forKey: "awakeCustomMinutes") as? Int ?? 90
        awakeDownloadTimeout = defaults.object(forKey: "awakeDownloadTimeout") as? Int ?? 30
        awakeWatchAI = bool("awakeWatchAI", true)
        awakeAIAllowDisplaySleep = bool("awakeAIAllowDisplaySleep", true)
        awakeAIStaleMinutes = defaults.object(forKey: "awakeAIStaleMinutes") as? Int ?? 30
        awakeAIGraceMinutes = defaults.object(forKey: "awakeAIGraceMinutes") as? Int ?? 3
        nearbyShowRadar = bool("nearbyShowRadar", true)
        proximityLockEnabled = bool("proximityLockEnabled", false)
        proximityLockDevices = defaults.dictionary(forKey: "proximityLockDevices") as? [String: String] ?? [:]
        proximityLockRequiresAll = bool("proximityLockRequiresAll", false)
        proximityLockGrace = defaults.object(forKey: "proximityLockGrace") as? Int ?? 30
        proximityLockUseDistance = bool("proximityLockUseDistance", false)
        proximityLockDistance = double("proximityLockDistance", 5)
        weatherLocationMode = string("weatherLocationMode", WeatherLocationMode.manual)
        weatherLocation = defaults.data(forKey: "weatherLocation").flatMap { try? JSONDecoder().decode(WeatherLocation.self, from: $0) }

        cpuBusyThreshold = double("cpuBusyThreshold", 0.8)
        temperatureHotThreshold = double("temperatureHotThreshold", 80)

        alertCPU = bool("alertCPU", false)
        alertCPUThreshold = double("alertCPUThreshold", 0.9)
        alertTemperature = bool("alertTemperature", false)
        alertTemperatureThreshold = double("alertTemperatureThreshold", 90)
        alertBatteryLow = bool("alertBatteryLow", false)
        alertBatteryLowThreshold = double("alertBatteryLowThreshold", 0.2)
        alertBatteryCharged = bool("alertBatteryCharged", false)
        alertBatteryChargedThreshold = double("alertBatteryChargedThreshold", 0.8)
        alertFans = bool("alertFans", false)
        alertAppCPU = bool("alertAppCPU", false)
        alertAppCPUThreshold = double("alertAppCPUThreshold", 0.8)
        alertDiskLow = bool("alertDiskLow", false)
        alertDiskLowThreshold = double("alertDiskLowThreshold", 0.1)
        alertNetworkDown = bool("alertNetworkDown", false)

        Format.fahrenheit = temperatureUnit == .fahrenheit
    }

    /// Default icon colors (validated palette steps), used when "Colora le icone" is on.
    static let defaultColors: [ModuleID: String] = [
        .cpu: "#2A78D6", .memory: "#1BAF7A", .disk: "#EDA100", .network: "#6250D6",
        .sensors: "#EB6834", .fans: "#E87BA4", .battery: "#008300", .weather: "#2A78D6", .date: "#6250D6", .awake: "#EDA100",
    ]

    func color(for series: GraphSeries) -> NSColor {
        NSColor(hex: graphSeriesColors[series] ?? "") ?? NSColor(hex: GraphSeries.defaultColors[series]!)!
    }

    func color(for module: ModuleID) -> NSColor {
        NSColor(hex: moduleColors[module] ?? "") ?? NSColor(hex: Settings.defaultColors[module]!)!
    }

    /// The color picked for one role of a tab; nil keeps the built-in one.
    func panelColorHex(_ tab: DashboardTab, _ role: Int) -> String? {
        if let series = tab.graphSeries(role: role) { return graphSeriesColors[series] }
        return panelColors[tab]?[role]
    }

    func isCustomPanelColor(_ tab: DashboardTab, _ role: Int) -> Bool {
        if let series = tab.graphSeries(role: role) { return graphSeriesColors[series] != GraphSeries.defaultColors[series] }
        return panelColors[tab]?[role] != nil
    }

    /// nil restores the built-in color.
    func setPanelColor(_ hex: String?, tab: DashboardTab, role: Int) {
        if let series = tab.graphSeries(role: role) {
            graphSeriesColors[series] = hex ?? GraphSeries.defaultColors[series]
            return
        }
        var roles = panelColors[tab] ?? [:]
        roles[role] = hex
        panelColors[tab] = roles.isEmpty ? nil : roles
    }

    /// The tab's main color when the user changed it (tab bar icon, map pin).
    func customColor(for tab: DashboardTab) -> Color? {
        guard isCustomPanelColor(tab, tab.primaryColorIndex) else { return nil }
        return panelColorHex(tab, tab.primaryColorIndex).flatMap(NSColor.init(hex:)).map(Color.init(nsColor:))
    }

    /// Enabled modules in the user's order.
    var visibleModules: [ModuleID] { moduleOrder.filter(enabledModules.contains) }

    func isEnabled(_ module: ModuleID) -> Bool { enabledModules.contains(module) }

    func shows(_ section: PanelSection) -> Bool { !hiddenSections.contains(section) }

    func setShown(_ section: PanelSection, _ shown: Bool) {
        if shown { hiddenSections.remove(section) } else { hiddenSections.insert(section) }
    }

    func setEnabled(_ module: ModuleID, _ enabled: Bool) {
        if enabled {
            enabledModules.insert(module)
        } else if enabledModules.count > 1 {
            // Keep at least one module, otherwise the app would have no UI left.
            enabledModules.remove(module)
        }
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}
