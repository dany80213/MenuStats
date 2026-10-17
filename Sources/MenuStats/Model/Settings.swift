import AppKit
import Combine
import Foundation

enum ModuleID: String, CaseIterable, Identifiable, Codable {
    case cpu, memory, disk, network, sensors, fans, battery, weather, date
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
        }
    }
}

enum DashboardTab: String, CaseIterable, Identifiable {
    case cpu, memory, disk, network, sensors, battery, weather, date
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
        }
    }

    /// Optional tabs only appear while their module is enabled.
    var isOptional: Bool { self == .weather || self == .date }
}

/// Optional sections of the dropdown. A hidden section is also not measured (no process list, no nettop,
/// no full sensor scan…), so hiding what you don't use makes MenuStats lighter.
enum PanelSection: String, CaseIterable, Identifiable, Codable {
    case cpuChart, cpuCores, cpuLoad, cpuProcesses
    case memoryComposition, memoryCharts, memoryProcesses
    case diskVolumes, diskChart, diskProcesses
    case networkChart, networkConnection, networkPublic, networkApps
    case sensorsChart, sensorsFans, sensorsGrid
    case batteryCharts, batteryHealth, batteryPower, batteryControls

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
        case .batteryHealth: "Salute"
        case .batteryPower: "Alimentazione"
        case .batteryControls: "Controlli"
        }
    }

    /// What hiding it saves, shown in Settings.
    var saving: String? {
        switch self {
        case .cpuProcesses, .memoryProcesses, .diskProcesses: "non elenca i processi"
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
        case .batteryCharts, .batteryHealth, .batteryPower, .batteryControls: .battery
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
        case .weather: .weather
        case .date: .date
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
    case activity, free, usedPercent
    var label: String { ["Lettura e scrittura", "Spazio libero", "Spazio usato (%)"][Self.allCases.firstIndex(of: self)!] }
}

enum NetworkStyle: String, StyleOption {
    case stacked, download, total
    var label: String { ["Upload e download", "Solo download", "Totale"][Self.allCases.firstIndex(of: self)!] }
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
    case percent, time, watts, iconOnly, insidePercent
    var label: String { ["Percentuale", "Tempo rimanente", "Potenza (W)", "Solo icona", "Percentuale nell'icona"][Self.allCases.firstIndex(of: self)!] }
}

enum DateStyle: String, StyleOption {
    case dayTime, time, timeSeconds, stacked, shortDate, numeric, long
    var label: String {
        ["Giorno e ora", "Solo ora", "Ora con secondi", "Data sopra l'ora", "Data breve", "Data numerica", "Data estesa"][Self.allCases.firstIndex(of: self)!]
    }
}

enum WeatherStyle: String, StyleOption {
    case iconTemperature, temperature, iconOnly, stacked
    var label: String { ["Icona e temperatura", "Solo temperatura", "Solo icona", "Città sopra la temperatura"][Self.allCases.firstIndex(of: self)!] }
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

    // Menu bar modules
    @Published var moduleOrder: [ModuleID] { didSet { save(moduleOrder.map(\.rawValue), "moduleOrder") } }
    @Published var enabledModules: Set<ModuleID> { didSet { save(enabledModules.map(\.rawValue), "enabledModules") } }

    // Styles
    @Published var cpuStyle: CPUStyle { didSet { save(cpuStyle.rawValue, "cpuStyle") } }
    @Published var memoryStyle: MemoryStyle { didSet { save(memoryStyle.rawValue, "memoryStyle") } }
    @Published var diskStyle: DiskStyle { didSet { save(diskStyle.rawValue, "diskStyle") } }
    @Published var networkStyle: NetworkStyle { didSet { save(networkStyle.rawValue, "networkStyle") } }
    @Published var sensorSource: SensorSource { didSet { save(sensorSource.rawValue, "sensorSource") } }
    @Published var fanStyle: FanStyle { didSet { save(fanStyle.rawValue, "fanStyle") } }
    @Published var batteryStyle: BatteryStyle { didSet { save(batteryStyle.rawValue, "batteryStyle") } }
    @Published var dateStyle: DateStyle { didSet { save(dateStyle.rawValue, "dateStyle") } }
    @Published var use24Hour: Bool { didSet { save(use24Hour, "use24Hour") } }
    @Published var weatherStyle: WeatherStyle { didSet { save(weatherStyle.rawValue, "weatherStyle") } }
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

        let savedOrder = (defaults.stringArray(forKey: "moduleOrder") ?? []).compactMap(ModuleID.init(rawValue:))
        moduleOrder = (savedOrder + ModuleID.allCases.filter { !savedOrder.contains($0) }).filter(\.isAvailable)
        enabledModules = Set((defaults.stringArray(forKey: "enabledModules")
            ?? ["cpu", "memory", "disk", "network", "sensors", "fans"]).compactMap(ModuleID.init(rawValue:)).filter(\.isAvailable))

        cpuStyle = string("cpuStyle", CPUStyle.graphPercent)
        memoryStyle = string("memoryStyle", MemoryStyle.ringPercent)
        diskStyle = string("diskStyle", DiskStyle.activity)
        networkStyle = string("networkStyle", NetworkStyle.stacked)
        sensorSource = string("sensorSource", SensorSource.cpuAverage)
        fanStyle = string("fanStyle", FanStyle.rpm)
        batteryStyle = string("batteryStyle", BatteryStyle.percent)
        dateStyle = string("dateStyle", DateStyle.dayTime)
        use24Hour = bool("use24Hour", true)
        weatherStyle = string("weatherStyle", WeatherStyle.iconTemperature)
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

        Format.fahrenheit = temperatureUnit == .fahrenheit
    }

    /// Default icon colors (validated palette steps), used when "Colora le icone" is on.
    static let defaultColors: [ModuleID: String] = [
        .cpu: "#2A78D6", .memory: "#1BAF7A", .disk: "#EDA100", .network: "#6250D6",
        .sensors: "#EB6834", .fans: "#E87BA4", .battery: "#008300", .weather: "#2A78D6", .date: "#6250D6",
    ]

    func color(for module: ModuleID) -> NSColor {
        NSColor(hex: moduleColors[module] ?? "") ?? NSColor(hex: Settings.defaultColors[module]!)!
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
