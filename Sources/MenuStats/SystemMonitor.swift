import Foundation

/// Everything the UI needs for one refresh.
struct Snapshot {
    var date = Date()
    var cpu: CPUStats?
    var memory: MemoryStats?
    var network: NetworkStats?
    var disk: DiskStats?
    var volumes: [VolumeInfo] = []
    var battery: BatteryStats?
    var sensors = SensorStats(readings: [])
    var smc: SMCStats?
    var processes: [ProcessUsage] = []
    var thermalState: ProcessInfo.ThermalState = .nominal
    var lowPowerMode = false

    var ssdTemperature: Double? { sensors.readings.first { $0.name.contains("NAND") }?.celsius }
    /// CPU temperature: average of the SMC per-core sensors; HID die sensors as fallback.
    var cpuTemperature: Double? { smc?.cpuTemperature ?? sensors.cpuAverage }
    var cpuTemperatureMax: Double? { smc?.cpuTemperatureMax ?? sensors.cpuMax }
    var gpuTemperature: Double? { smc?.gpuTemperature }
    var maxFanRPM: Double? { smc?.fans.map(\.rpm).max() }
    var fansSpinning: Bool { (maxFanRPM ?? 0) > 0 }
}

/// What is on screen right now. The monitor reads expensive sources often only when something shows them;
/// otherwise they refresh slowly (for history and alerts) or not at all (process lists, volumes).
struct SamplingDemand: Equatable {
    /// Modules visible in the menu bar.
    var menubar: Set<ModuleID> = Set(ModuleID.allCases)
    /// The dashboard tab on screen, nil while the dropdown is closed.
    var tab: DashboardTab?
    /// Dropdown sections the user hid: their data isn't collected.
    var hidden: Set<PanelSection> = []

    var panelOpen: Bool { tab != nil }

    /// True when `section` is on screen right now.
    func shows(_ section: PanelSection) -> Bool { tab == section.tab && !hidden.contains(section) }
}

/// Owns the readers and produces one Snapshot per refresh, doing only the work the current demand needs.
final class SystemMonitor {
    var demand = SamplingDemand()

    private let cpuReader = CPUReader()
    private let memoryReader = MemoryReader()
    private let networkReader = NetworkReader()
    private let diskReader = DiskReader()
    private let batteryReader = BatteryReader()
    private let smcReader = SMCReader()
    private let processReader = ProcessReader()

    // HID temperature services cost ~1 ms each: read on a background queue and cached.
    private let sensorsReader = SensorsReader()
    private let sensorsQueue = DispatchQueue(label: "MenuStats.sensors", qos: .utility)
    private var sensors = SensorStats(readings: [])
    private var sensorsTime = -Double.infinity
    private var sensorsInFlight = false

    private var volumes: [VolumeInfo] = []
    private var volumesTime = -Double.infinity

    func sample() -> Snapshot {
        let now = uptimeSeconds()
        let tab = demand.tab

        // Process lists, volumes and the full sensor scan exist only in their dropdown sections.
        // (The network tab needs the process list to name nettop's apps.)
        let wantsProcesses = demand.shows(.cpuProcesses) || demand.shows(.memoryProcesses)
            || demand.shows(.diskProcesses) || demand.shows(.networkApps)
        if demand.shows(.diskVolumes), now - volumesTime > 10 {
            volumes = VolumeReader.sample()
            volumesTime = now
        }
        refreshSensorsIfNeeded(now: now)

        var live: Set<SMCReader.Part> = []
        if demand.menubar.contains(.fans) || demand.shows(.sensorsFans) { live.insert(.fans) }
        if demand.menubar.contains(.sensors) || tab == .sensors { live.insert(.cpuTemperatures) }
        if demand.shows(.sensorsGrid) { live.insert(.gpuTemperatures) }
        if demand.shows(.sensorsFans) || demand.shows(.batteryCharts) { live.insert(.power) }

        return Snapshot(
            cpu: cpuReader.sample(),
            memory: memoryReader.sample(),
            network: networkReader.sample(),
            disk: diskReader.sample(),
            volumes: demand.shows(.diskVolumes) ? volumes : [],
            battery: batteryReader.sample(),
            sensors: sensors,
            smc: smcReader.sample(live: live),
            processes: wantsProcesses ? processReader.sample() : [],
            thermalState: ProcessInfo.processInfo.thermalState,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    /// Forgets slow caches so the next sample is complete, e.g. when the dropdown opens on a tab.
    func refreshSoon() {
        volumesTime = -.infinity
        sensorsTime = -.infinity
        batteryReader.invalidateDetails()
    }

    /// Synchronous full read, for one-shot tools (`--dump`, `--verify`, `--render-ui`).
    func sampleSensorsNow() {
        sensors = sensorsQueue.sync { sensorsReader.sample(full: true) }
        sensorsTime = uptimeSeconds()
    }

    private func refreshSensorsIfNeeded(now: Double) {
        // All ~45 services while the sensors tab is open (every sample); otherwise only the SSD/battery
        // sensors (and the die sensors on chips without an SMC core map) every 10 s.
        let full = demand.shows(.sensorsGrid)
        let interval: Double = full ? 0 : 10
        guard !sensorsInFlight, now - sensorsTime >= interval - 0.1 else { return }
        sensorsInFlight = true
        let includeDie = !smcReader.hasCoreMap
        sensorsQueue.async { [self] in
            let readings = sensorsReader.sample(full: full, includeDie: includeDie)
            DispatchQueue.main.async { [self] in
                sensors = readings
                sensorsTime = uptimeSeconds()
                sensorsInFlight = false
            }
        }
    }
}
