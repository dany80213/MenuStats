import SwiftUI

// MARK: - CPU

struct CPUTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let snapshot = model.snapshot
        VStack(spacing: 8) {
            if let cpu = snapshot.cpu {
                Card {
                    HStack(alignment: .top) {
                        Hero(value: Format.percent(cpu.total), caption: cpu.brand)
                        Spacer()
                        StatGrid(items: [
                            ("Utente", Format.percent(cpu.user)),
                            ("Sistema", Format.percent(cpu.system)),
                            ("Inattiva", Format.percent(1 - cpu.total)),
                        ], columns: 1)
                        .frame(width: 120)
                    }
                    if settings.shows(.cpuChart) {
                        MetricChart(model: model, title: "Utilizzo", lines: [
                            ChartLine(metric: .cpuUser, name: "Utente", color: 0),
                            ChartLine(metric: .cpuSystem, name: "Sistema", color: 1),
                        ], scale: .percent, stacked: true)
                        .hideable(.cpuChart)
                    }
                }

                if settings.shows(.cpuCores) {
                    Card(title: "Core", trailing: cpu.efficiencyCores > 0 ? "\(cpu.performanceCores)P + \(cpu.efficiencyCores)E" : nil) {
                        CoreBars(cpu: cpu)
                    }
                    .hideable(.cpuCores)
                }

                if settings.shows(.cpuLoad) {
                Card(title: "Carico") {
                    StatGrid(items: [
                        ("1 min", String(format: "%.2f", cpu.loadAverage[0])),
                        ("5 min", String(format: "%.2f", cpu.loadAverage[1])),
                        ("15 min", String(format: "%.2f", cpu.loadAverage[2])),
                        ("Attivo da", Format.uptime()),
                    ])
                }
                .hideable(.cpuLoad)
                }
            }

            if settings.shows(.cpuProcesses) {
                Card(title: "Processi", trailing: settings.groupProcessesByApp ? "per app" : nil) {
                    ProcessList(rows: ProcessGrouping.groups(snapshot.processes, byApp: settings.groupProcessesByApp),
                                count: settings.processCount, value: \.cpu, label: { Format.processCPU($0.cpu) })
                }
                .hideable(.cpuProcesses)
            }
        }
    }
}

/// Per-core usage bars, efficiency cores first (Apple Silicon numbers them first), then performance cores.
struct CoreBars: View {
    var cpu: CPUStats
    private let barHeight: CGFloat = 40

    var body: some View {
        let efficiency = min(cpu.efficiencyCores, cpu.perCore.count)
        let groups: [(title: String, cores: [Double], color: Int)] = efficiency > 0
            ? [("Efficienza", Array(cpu.perCore.prefix(efficiency)), 2), ("Prestazioni", Array(cpu.perCore.dropFirst(efficiency)), 0)]
            : [("", cpu.perCore, 0)]
        let groupGap: CGFloat = 12, barGap: CGFloat = 3

        GeometryReader { geometry in
            let count = CGFloat(cpu.perCore.count)
            let gaps = groupGap * CGFloat(groups.count - 1) + barGap * (count - CGFloat(groups.count))
            let barWidth = max(4, (geometry.size.width - gaps) / max(count, 1))
            HStack(alignment: .top, spacing: groupGap) {
                ForEach(groups.indices, id: \.self) { index in
                    let group = groups[index]
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .bottom, spacing: barGap) {
                            ForEach(group.cores.indices, id: \.self) { core in
                                let usage = min(max(group.cores[core], 0), 1)
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 2.5).fill(Palette.neutral)
                                    RoundedRectangle(cornerRadius: 2.5).fill(Palette.color(group.color))
                                        .frame(height: max(3, barHeight * CGFloat(usage)))
                                }
                                .frame(width: barWidth, height: barHeight)
                                .help(Format.percent(usage))
                            }
                        }
                        if !group.title.isEmpty {
                            Text("\(group.title) · \(Format.percent(group.cores.reduce(0, +) / Double(max(group.cores.count, 1))))")
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                        }
                    }
                }
            }
        }
        .frame(height: barHeight + 18)
    }
}

// MARK: - Memory

struct MemoryTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let snapshot = model.snapshot
        VStack(spacing: 8) {
            if let memory = snapshot.memory {
                Card {
                    HStack(alignment: .top) {
                        Hero(value: Format.percent(memory.usedFraction),
                             caption: "\(Format.bytes(memory.used)) di \(Format.bytes(memory.total))")
                        Spacer()
                        StatusBadge(label: "Pressione " + (memory.pressureLevel >= 4 ? "critica" : memory.pressureLevel >= 2 ? "alta" : "normale"),
                                    level: memory.pressureLevel >= 4 ? .critical : memory.pressureLevel >= 2 ? .warning : .good)
                    }
                    if settings.shows(.memoryComposition) {
                    StackedBar(segments: [
                        .init(name: "App", value: Double(memory.app), color: Palette.color(0), label: Format.bytes(memory.app)),
                        .init(name: "Wired", value: Double(memory.wired), color: Palette.color(1), label: Format.bytes(memory.wired)),
                        .init(name: "Compressa", value: Double(memory.compressed), color: Palette.color(2), label: Format.bytes(memory.compressed)),
                        .init(name: "Cache", value: Double(memory.cached), color: Palette.color(3), label: Format.bytes(memory.cached)),
                        .init(name: "Libera", value: Double(memory.free), color: Palette.neutral, label: Format.bytes(memory.free)),
                    ])
                    .hideable(.memoryComposition)
                    }
                }
                if settings.shows(.memoryCharts) {
                    Card {
                        MetricChart(model: model, title: "Memoria usata", lines: [ChartLine(metric: .memory, name: "Memoria", color: 0)], scale: .percent)
                        MetricChart(model: model, title: "Swap", lines: [ChartLine(metric: .swap, name: "Swap", color: 1)], scale: .bytes, height: 50)
                    }
                    .hideable(.memoryCharts)
                }
            }
            if settings.shows(.memoryProcesses) {
                Card(title: "Processi", trailing: settings.groupProcessesByApp ? "per app" : nil) {
                    ProcessList(rows: ProcessGrouping.groups(snapshot.processes, byApp: settings.groupProcessesByApp),
                                count: settings.processCount, value: { Double($0.memory) }, label: { Format.bytes($0.memory) })
                }
                .hideable(.memoryProcesses)
            }
        }
    }
}

// MARK: - Disk

struct DiskTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let snapshot = model.snapshot
        VStack(spacing: 8) {
            if settings.shows(.diskVolumes) {
                Card(title: "Volumi") {
                    VStack(spacing: 12) {
                        ForEach(snapshot.volumes) { volume in
                            VolumeRow(volume: volume)
                        }
                    }
                }
                .hideable(.diskVolumes)
            }
            if settings.shows(.diskChart) {
                Card {
                    MetricChart(model: model, title: "Attività", lines: [
                        ChartLine(metric: .diskRead, name: "Lettura", color: 0),
                        ChartLine(metric: .diskWrite, name: "Scrittura", color: 1),
                    ], scale: .rate)
                }
                .hideable(.diskChart)
            }
            if settings.shows(.diskProcesses) {
                Card(title: "Processi", trailing: "lettura + scrittura") {
                    ProcessList(rows: ProcessGrouping.groups(snapshot.processes, byApp: settings.groupProcessesByApp),
                                count: settings.processCount, value: { $0.diskRead + $0.diskWrite },
                                label: { "R \(Format.rate($0.diskRead, compact: true))  W \(Format.rate($0.diskWrite, compact: true))" })
                }
                .hideable(.diskProcesses)
            }
        }
    }
}

/// One volume: used / purgeable / free bar with exact figures (free = truly free, as `df` reports).
struct VolumeRow: View {
    var volume: VolumeInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: volume.isNetwork ? "server.rack" : volume.isRemovable ? "externaldrive" : "internaldrive")
                    .foregroundStyle(.secondary).frame(width: 16)
                Text(volume.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                Text("\(Format.percent(volume.usedFraction)) usato").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            StackedBar(segments: [
                .init(name: "Usato", value: Double(volume.used - min(volume.used, volume.purgeable)), color: usedColor,
                      label: Format.storage(volume.used - min(volume.used, volume.purgeable))),
                .init(name: "Eliminabile", value: Double(volume.purgeable), color: Palette.color(3), label: Format.storage(volume.purgeable)),
                .init(name: "Libero", value: Double(volume.free), color: Palette.neutral, label: Format.storage(volume.free)),
            ])
            Text("Totale \(Format.storage(volume.total)) · disponibili \(Format.storage(volume.available)) contando lo spazio che macOS libera da solo (cache, istantanee locali)")
                .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var usedColor: Color {
        volume.free < volume.total / 20 ? .red : volume.free < volume.total / 10 ? .orange : Palette.color(0)
    }
}

// MARK: - Network

struct NetworkTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let snapshot = model.snapshot
        VStack(spacing: 8) {
            if let network = snapshot.network {
                Card {
                    HStack {
                        Hero(value: Format.rate(network.downloadRate), caption: "Download", accent: Palette.color(0))
                        Spacer()
                        Hero(value: Format.rate(network.uploadRate), caption: "Upload", accent: Palette.color(1))
                        Spacer()
                    }
                    if settings.shows(.networkChart) {
                        MetricChart(model: model, title: "Traffico", lines: [
                            ChartLine(metric: .netDown, name: "Download", color: 0),
                            ChartLine(metric: .netUp, name: "Upload", color: 1),
                        ], scale: .rate)
                        .hideable(.networkChart)
                    }
                }
                if settings.shows(.networkConnection) {
                Card(title: "Connessione") {
                    StatGrid(items: [
                        ("Interfaccia", network.interface ?? "Non connesso"),
                        ("Indirizzo IP", network.ipAddress ?? "—"),
                        ("Ricevuti", Format.storage(network.totalDownloaded)),
                        ("Inviati", Format.storage(network.totalUploaded)),
                    ], columns: 1)
                }
                .hideable(.networkConnection)
                }
            }
            if settings.shows(.networkPublic), settings.publicIPEnabled || settings.showVPN {
                PublicNetworkCard(model: model, settings: settings)
                    .hideable(.networkPublic)
            }
            if settings.shows(.networkApps) {
                Card(title: "App", trailing: "download + upload") {
                    ProcessList(rows: ProcessGrouping.networkGroups(model.networkProcesses, processes: snapshot.processes,
                                                                    byApp: settings.groupProcessesByApp),
                                count: settings.processCount, value: { $0.networkDown + $0.networkUp },
                                label: { "↓\(Format.rate($0.networkDown, compact: true))  ↑\(Format.rate($0.networkUp, compact: true))" },
                                emptyText: "Misurazione in corso…")
                }
                .hideable(.networkApps)
            }
        }
        // nettop (per-app traffic) runs only while the section is on screen.
        .onAppear { model.setNetworkProcessSampling(settings.shows(.networkApps)) }
        .onDisappear { model.setNetworkProcessSampling(false) }
        .onChange(of: settings.shows(.networkApps)) { model.setNetworkProcessSampling($0) }
    }
}

/// Public IP (with country flag) and VPN status, each switchable in Settings ▸ Rete.
struct PublicNetworkCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    @ObservedObject private var service: PublicNetworkService
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    init(model: AppModel, settings: Settings) {
        self.model = model
        self.settings = settings
        _service = ObservedObject(wrappedValue: model.publicNetwork)
    }

    var body: some View {
        Card(title: "IP pubblico e VPN") {
            if settings.publicIPEnabled {
                row("IP pubblico", publicValue, detail: service.publicIP.flatMap { [$0.country, $0.provider].compactMap { $0 }.joined(separator: " · ") })
                if settings.showIPv6, let v6 = service.publicIP?.ipv6 { row("IPv6", v6, detail: nil) }
            }
            if settings.showVPN {
                row("VPN", service.vpn == nil ? "Non attiva" : "Attiva",
                    detail: service.vpn.map { vpn in
                        [vpn.name, vpn.interface, vpn.fullTunnel ? "tutto il traffico" : "traffico parziale"].compactMap { $0 }.joined(separator: " · ")
                    })
                if let vpn = service.vpn {
                    let flag = settings.showVPNCountry ? service.publicIP?.flag.map { $0 + " " } ?? "" : ""
                    row("IP della VPN", flag + vpn.address, detail: nil)
                }
            }
        }
        .onAppear(perform: update)
        .onReceive(tick) { _ in update() }
        .onChange(of: settings.publicIPEnabled) { _ in update() }
        .onChange(of: settings.showVPNCountry) { _ in update() }
    }

    private var publicValue: String {
        if let ip = service.publicIP {
            let flag = settings.showCountryFlag ? ip.flag.map { $0 + " " } ?? "" : ""
            return flag + ip.address
        }
        return service.error ?? "…"
    }

    private func update() {
        let network = model.snapshot.network
        service.update(defaultInterface: network?.interface, localAddress: network?.ipAddress,
                       publicIPEnabled: settings.publicIPEnabled, vpnEnabled: settings.showVPN,
                       vpnCountryEnabled: settings.showVPNCountry)
    }

    private func row(_ title: String, _ value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(value).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65).truncationMode(.middle).textSelection(.enabled)
            }
            .font(.system(size: 11.5))
            if let detail, !detail.isEmpty {
                Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

// MARK: - Sensors

struct SensorsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let snapshot = model.snapshot
        let sensors = snapshot.sensors
        VStack(spacing: 8) {
            Card {
                HStack(alignment: .top) {
                    Hero(value: snapshot.cpuTemperature.map { Format.temperature($0) } ?? "—",
                         caption: snapshot.cpuTemperatureMax.map { "CPU (media dei core) · massima \(Format.temperature($0))" } ?? "CPU")
                    Spacer()
                    thermalBadge(snapshot.thermalState)
                }
                if settings.shows(.sensorsChart) {
                    MetricChart(model: model, title: "Temperature", lines: [
                        ChartLine(metric: .cpuTemp, name: "CPU", color: 0),
                        ChartLine(metric: .ssdTemp, name: "SSD", color: 1),
                    ], scale: .temperature)
                    .hideable(.sensorsChart)
                }
            }

            if settings.shows(.sensorsFans), let smc = snapshot.smc, !smc.fans.isEmpty || smc.systemPower != nil {
                Card(title: "Ventole e alimentazione") {
                    ForEach(smc.fans) { fan in FanRow(fan: fan, hardware: model.hardware) }
                    StatGrid(items: [
                        ("Consumo sistema", smc.systemPower.map(Format.watts) ?? "—"),
                        ("Alimentatore", (smc.adapterPower ?? 0) > 0.5 ? Format.watts(smc.adapterPower!) : "Scollegato"),
                    ])
                    .padding(.top, 2)
                    if !smc.fans.isEmpty {
                        MetricChart(model: model, title: "Velocità ventole", lines: [ChartLine(metric: .fan, name: "Ventole", color: 2)],
                                    scale: .rpm, height: 50)
                    }
                    MetricChart(model: model, title: "Consumo", lines: [ChartLine(metric: .power, name: "Sistema", color: 3)],
                                scale: .watts, height: 50)
                }
                .hideable(.sensorsFans)
            }

            if settings.shows(.sensorsGrid) {
            Card(title: "Sensori", trailing: "\(sensors.readings.count + (snapshot.smc?.cpuCoreTemperatures.count ?? 0) + (snapshot.smc?.gpuTemperatures.count ?? 0))") {
                SensorGrid(readings: sensors.readings, smc: snapshot.smc)
            }
            .hideable(.sensorsGrid)
            }
        }
    }

    private func thermalBadge(_ state: ProcessInfo.ThermalState) -> some View {
        switch state {
        case .nominal: StatusBadge(label: "Termica normale", level: .good)
        case .fair: StatusBadge(label: "Termica moderata", level: .warning)
        case .serious: StatusBadge(label: "Rallentamento", level: .critical)
        default: StatusBadge(label: "Critica", level: .critical)
        }
    }
}

struct FanRow: View {
    var fan: FanInfo
    @ObservedObject var hardware: HardwareControl
    @State private var draft: Double?

    private var target: Double? { hardware.fanTargets[fan.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SpinningFan(rpm: fan.rpm, maximum: fan.maximum)
                Text(fan.name).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(fan.rpm > 0 ? Format.rpm(fan.rpm) : "Ferma").font(.system(size: 12)).monospacedDigit()
                Text(Format.percent(fan.fraction))
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Palette.color(2).opacity(0.15)))
                    .help("Percentuale della velocità massima")
            }
            UsageBar(fraction: fan.fraction, color: Palette.color(2), height: 5)
            Text("min \(Format.rpm(fan.minimum)) · max \(Format.rpm(fan.maximum))")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            if fan.maximum > fan.minimum, fan.minimum > 0 {
                controls
            }
        }
    }

    @ViewBuilder private var controls: some View {
        Picker("", selection: Binding(get: { target != nil }, set: { custom in
            hardware.setFan(fan.id, rpm: custom ? (target ?? max(fan.rpm, fan.minimum)) : nil)
        })) {
            Text("Auto").tag(false)
            Text("Personalizzato").tag(true)
        }
        .pickerStyle(.segmented).labelsHidden().controlSize(.small)
        .disabled(!hardware.canUseHelper || hardware.busy)
        if let target {
            HStack(spacing: 6) {
                Slider(value: Binding(get: { draft ?? target }, set: { draft = $0 }),
                       in: fan.minimum...fan.maximum, step: 100) { editing in
                    if !editing, let value = draft {
                        hardware.setFan(fan.id, rpm: value)
                        draft = nil
                    }
                }
                .controlSize(.small)
                Text(Format.rpm(draft ?? target)).font(.system(size: 11)).monospacedDigit().frame(width: 72, alignment: .trailing)
            }
        }
        if !hardware.canUseHelper {
            Text("Per il controllo installa l'helper in Impostazioni ▸ Ventole.").font(.system(size: 10)).foregroundStyle(.secondary)
        } else if let error = hardware.fanError {
            Text(error).font(.system(size: 10)).foregroundStyle(.red)
        }
    }
}

/// Fan symbol that rotates with a speed proportional to the fan's RPM.
struct SpinningFan: View {
    var rpm: Double
    var maximum: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: rpm <= 0)) { context in
            let revolutionsPerSecond = rpm > 0 ? 0.4 + 1.6 * min(rpm / max(maximum, 1), 1) : 0
            let angle = context.date.timeIntervalSinceReferenceDate * revolutionsPerSecond * 360
            Image(systemName: "fan")
                .rotationEffect(.degrees(angle.truncatingRemainder(dividingBy: 360)))
                .foregroundStyle(rpm > 0 ? Palette.color(2) : Color.secondary)
        }
        .frame(width: 16, height: 16)
    }
}

/// Sensors grouped by kind, as compact cells.
struct SensorGrid: View {
    var readings: [SensorReading]
    var smc: SMCStats? = nil

    private var groups: [(String, [SensorReading])] {
        let cores = (smc?.cpuCoreTemperatures ?? []).enumerated().map { SensorReading(name: "\($0.offset + 1)", celsius: $0.element) }
        let gpu = (smc?.gpuTemperatures ?? []).enumerated().map { SensorReading(name: "\($0.offset + 1)", celsius: $0.element) }
        let smcGroups = [("Core CPU", cores), ("GPU", gpu)].filter { !$0.1.isEmpty }
        return smcGroups + hidGroups
    }

    private var hidGroups: [(String, [SensorReading])] {
        let die = readings.filter { $0.name.contains("tdie") }
        let device = readings.filter { $0.name.contains("tdev") }
        let other = readings.filter { !$0.name.contains("tdie") && !$0.name.contains("tdev") }
        return [("Die CPU", die), ("SoC", device), ("Altri", other)].filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groups, id: \.0) { title, readings in
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: title == "Altri" ? 2 : 5), spacing: 4) {
                        ForEach(readings, id: \.name) { reading in
                            HStack(spacing: 3) {
                                Text(shortName(reading.name, group: title)).foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: 2)
                                Text(Format.temperature(reading.celsius, unit: false)).monospacedDigit()
                            }
                            .font(.system(size: 10.5))
                            .padding(.horizontal, 5)
                            .frame(height: 20)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill(Palette.color(1).opacity(heat(reading.celsius))))
                        }
                    }
                }
            }
        }
    }

    /// Sequential single-hue intensity: 30 °C → faint, 100 °C → strong.
    private func heat(_ celsius: Double) -> Double { 0.06 + 0.34 * min(max((celsius - 30) / 70, 0), 1) }

    private func shortName(_ name: String, group: String) -> String {
        switch group {
        case "Core CPU", "GPU": name
        case "Die CPU", "SoC": name.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        default: name.replacingOccurrences(of: "gas gauge battery", with: "Batteria")
                     .replacingOccurrences(of: "NAND CH0 temp", with: "SSD")
                     .replacingOccurrences(of: "PMU tcal", with: "Calibrazione")
        }
    }
}

// MARK: - Battery

struct BatteryTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings = Settings.shared
    @State private var changingLowPower = false

    var body: some View {
        let snapshot = model.snapshot
        VStack(spacing: 8) {
            if let battery = snapshot.battery {
                Card {
                    HStack(alignment: .top) {
                        Hero(value: Format.percent(battery.percent), caption: stateText(battery))
                        Spacer()
                        Image(systemName: batterySymbol(battery))
                            .font(.system(size: 26))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(battery.percent <= 0.2 && !battery.onACPower ? Color.red : Palette.color(2))
                    }
                    UsageBar(fraction: battery.percent, color: Palette.color(2), height: 7)
                    if settings.shows(.batteryCharts) {
                        Group {
                            MetricChart(model: model, title: "Carica", lines: [ChartLine(metric: .battery, name: "Carica", color: 2)], scale: .percent)
                            MetricChart(model: model, title: "Potenza (+ in carica, − in uso)",
                                        lines: [ChartLine(metric: .batteryPower, name: "Potenza", color: 3)], scale: .watts, height: 50)
                        }
                        .hideable(.batteryCharts)
                    }
                }
                if settings.shows(.batteryHealth) {
                Card(title: "Salute") {
                    StatGrid(items: [
                        ("Capacità massima", battery.health.map { Format.percent($0) + (battery.healthIsOfficial ? "" : " (stima)") } ?? "—"),
                        ("Cicli", battery.cycleCount.map { "\($0)" } ?? "—"),
                        ("Condizione", battery.condition ?? "—"),
                        ("A piena carica", battery.fullChargeCapacity.map { "\($0) mAh" } ?? "—"),
                        ("Di fabbrica", battery.designCapacity.map { "\($0) mAh" } ?? "—"),
                        ("Carica residua", battery.remainingCapacity.map { "\($0) mAh" } ?? "—"),
                        ("Temperatura", (battery.temperature ?? snapshot.sensors.batteryTemperature).map { Format.temperature($0) } ?? "—"),
                    ])
                }
                .hideable(.batteryHealth)
                }
                if settings.shows(.batteryPower) {
                Card(title: "Alimentazione") {
                    StatGrid(items: [
                        ("Potenza", battery.watts.map { String(format: "%+.1f W", $0) } ?? "—"),
                        ("Tensione", battery.voltage.map { String(format: "%.2f V", $0) } ?? "—"),
                        ("Corrente", battery.amperage.map { String(format: "%+.2f A", $0) } ?? "—"),
                        ("Alimentatore", battery.adapterWatts.map { "\($0) W" } ?? (battery.onACPower ? "Sì" : "No")),
                    ])
                }
                .hideable(.batteryPower)
                }
                if settings.shows(.batteryControls) {
                Card(title: "Controlli") {
                    Toggle(isOn: Binding(get: { snapshot.lowPowerMode }, set: { enabled in
                        changingLowPower = true
                        SystemActions.setLowPowerMode(enabled) { changingLowPower = false; model.tick() }
                    })) {
                        Label("Modalità basso consumo", systemImage: "leaf")
                    }
                    .toggleStyle(.switch).controlSize(.small).disabled(changingLowPower)
                    ChargeLimitPicker(hardware: model.hardware)
                    Button { SystemActions.openBatterySettings() } label: {
                        Label("Impostazioni Batteria…", systemImage: "gearshape")
                    }
                    .buttonStyle(.link).font(.system(size: 12))
                }
                .hideable(.batteryControls)
                }
            } else {
                Card { Text("Nessuna batteria: il Mac è alimentato dalla rete.").foregroundStyle(.secondary) }
            }
        }
    }

    private func stateText(_ battery: BatteryStats) -> String {
        if battery.isFullyCharged { return "Carica completa" }
        if battery.isCharging {
            return battery.minutesRemaining.map { "In carica · piena tra \(Format.duration(minutes: $0))" } ?? "In carica"
        }
        if battery.onACPower { return "Collegato · non in carica" }
        return battery.minutesRemaining.map { "A batteria · \(Format.duration(minutes: $0)) rimanenti" } ?? "A batteria"
    }

    private func batterySymbol(_ battery: BatteryStats) -> String {
        if battery.isCharging { return "battery.100percent.bolt" }
        let level = Int((battery.percent * 4).rounded()) * 25
        return "battery.\(level)percent"
    }
}

/// Charge limit 80 / 90 / 100 %, the same setting as System Settings ▸ Battery ▸ Charge Limit.
struct ChargeLimitPicker: View {
    @ObservedObject var hardware: HardwareControl

    var body: some View {
        if hardware.chargeLimitSupported {
            HStack {
                Label("Limite di carica", systemImage: "battery.75percent")
                Spacer()
                Picker("", selection: Binding(get: { hardware.chargeLimit ?? 100 }, set: { hardware.setChargeLimit($0) })) {
                    ForEach(HardwareControl.chargeLimits, id: \.self) { Text("\($0)%").tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
            }
            if let error = hardware.chargeError {
                Text(error).font(.system(size: 10)).foregroundStyle(.red)
            }
        }
    }
}
