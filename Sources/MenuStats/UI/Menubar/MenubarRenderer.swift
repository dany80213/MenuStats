import AppKit

/// One module's drawing in the menu bar.
struct MenubarSegment {
    var module: ModuleID
    var width: CGFloat
    var draw: (NSRect) -> Void
}

/// Draws the compact menu bar: every module as a small segment (visual + label/value).
/// Monochrome by default (a template image macOS tints for light and dark menu bars); optionally colored
/// per module, and automatically yellow → orange → red when a module needs attention.
/// Dynamic icons react to what the Mac is doing (load, heat, fans, charging, traffic).
enum MenubarRenderer {
    static let height: CGFloat = 22
    static let segmentGap: CGFloat = 10

    struct Context {
        var snapshot: Snapshot
        var options: MenubarOptions
        var recent: (Metric, Int) -> [Double]
        /// Fan animation angle in radians, advanced by the status bar controller while fans spin.
        var fanAngle: CGFloat = 0
        /// Where the steam's waves are (0…1, wraps). The menu bar keeps 0: the cup's steam is drawn still.
        var steamPhase: CGFloat = 0
        var weather: WeatherReport? = nil
        var weatherConfigured = false
        var awake = AwakeState()
        var now = Date()
    }

    // MARK: - Composition

    static func image(for modules: [ModuleID], context: Context) -> (image: NSImage, hitRanges: [(ModuleID, ClosedRange<CGFloat>)]) {
        let segments = modules.map { segment(for: $0, context: context) }
        let width = max(1, segments.map(\.width).reduce(0, +) + segmentGap * CGFloat(max(segments.count - 1, 0)))
        var ranges: [(ModuleID, ClosedRange<CGFloat>)] = []
        var x: CGFloat = 0
        for segment in segments {
            // Click targets extend halfway into the gaps.
            ranges.append((segment.module, (x - segmentGap / 2)...(x + segment.width + segmentGap / 2)))
            x += segment.width + segmentGap
        }

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for segment in segments {
                segment.draw(NSRect(x: x, y: 0, width: segment.width, height: height))
                x += segment.width + segmentGap
            }
            return true
        }
        // Monochrome stays a template (macOS tints it); with colors the image carries its own (adaptive) colors.
        image.isTemplate = !context.options.usesColor
        return (image, ranges)
    }

    static func segment(for module: ModuleID, context: Context) -> MenubarSegment {
        let options = context.options
        showLabels = options.showLabels
        ink = Ink(module: module, options: options, severity: Severity.of(
            module, snapshot: context.snapshot, cpuBusy: options.cpuBusyThreshold,
            temperatureHot: options.temperatureHotThreshold, source: options.sensorSource))
        return switch module {
        case .cpu: cpu(context)
        case .memory: memory(context)
        case .disk: disk(context)
        case .network: network(context)
        case .sensors: sensors(context)
        case .fans: fans(context)
        case .battery: battery(context)
        case .weather: weather(context)
        case .date: date(context)
        case .awake: awake(context)
        }
    }

    // MARK: - Modules

    private static func cpu(_ context: Context) -> MenubarSegment {
        let settings = context.options
        let cpu = context.snapshot.cpu
        let total = cpu?.total ?? 0
        let busy = settings.dynamicIcons && total >= settings.cpuBusyThreshold
        let value = cpu.map { Format.percent($0.total) } ?? "—"

        var parts: [Part] = []
        switch settings.cpuStyle {
        case .graphPercent:
            parts = [.graph(context.recent(.cpu, 15), width: 30), .text("CPU", value, template: "100%", emphasized: busy)]
        case .percent:
            parts = [.text("CPU", value, template: "100%", emphasized: busy)]
        case .graph:
            parts = [.graph(context.recent(.cpu, 20), width: 40)]
        case .cores:
            parts = [.cores(cpu?.perCore ?? [])]
        }
        if busy { parts.insert(.symbol("flame.fill", size: 9), at: parts.count - (parts.count > 1 ? 1 : 0)) }
        return compose(.cpu, parts)
    }

    private static func memory(_ context: Context) -> MenubarSegment {
        let memory = context.snapshot.memory
        let pressured = context.options.dynamicIcons && (memory?.pressureLevel ?? 1) >= 2
        let fraction = memory?.usedFraction ?? 0

        let lead: Part = pressured ? .symbol("exclamationmark.triangle.fill", size: 11) : .ring(fraction)
        switch context.options.memoryStyle {
        case .ringPercent:
            return compose(.memory, [lead, .text("MEM", Format.percent(fraction), template: "100%")])
        case .percent:
            return compose(.memory, [.text("MEM", Format.percent(fraction), template: "100%", emphasized: pressured)])
        case .used:
            let used = memory.map { String(format: "%.1fG", Double($0.used) / 1_073_741_824) } ?? "—"
            return compose(.memory, [lead, .text("MEM", used, template: "99.9G")])
        case .pressure:
            let label = [1: "OK", 2: "ALTA", 4: "CRIT"][memory?.pressureLevel ?? 1] ?? "—"
            return compose(.memory, [lead, .text("PRESS", label, template: "CRIT", emphasized: pressured)])
        }
    }

    private static func disk(_ context: Context) -> MenubarSegment {
        guard let disk = context.snapshot.disk else { return compose(.disk, [.text("SSD", "—", template: "100%")]) }
        let dynamic = context.options.dynamicIcons
        switch context.options.diskStyle {
        case .activity:
            let reading = disk.readRate > 64_000, writing = disk.writeRate > 64_000
            return compose(.disk, [
                .stacked(top: ("R", Format.rate(disk.readRate, compact: true), !dynamic || reading),
                         bottom: ("W", Format.rate(disk.writeRate, compact: true), !dynamic || writing)),
            ])
        case .free:
            let free = Format.storageCompact(disk.free)
            return compose(.disk, [.symbol("internaldrive", size: 12), .text("LIBERO", free, template: "999G")])
        case .usedPercent:
            return compose(.disk, [.ring(disk.usedFraction), .text("SSD", Format.percent(disk.usedFraction), template: "100%")])
        case .graphs, .graphsValues:
            let options = context.options
            let graph = Part.dualGraph(top: context.recent(.diskWrite, 20), bottom: context.recent(.diskRead, 20),
                                       topColor: options.graphColor(.write), bottomColor: options.graphColor(.read),
                                       floor: 1_000_000, width: options.diskStyle == .graphs ? 40 : 30)
            guard options.diskStyle == .graphsValues else { return compose(.disk, [graph]) }
            let reading = disk.readRate > 64_000, writing = disk.writeRate > 64_000
            return compose(.disk, [graph, .stacked(top: ("W", Format.rate(disk.writeRate, compact: true), !dynamic || writing),
                                                   bottom: ("R", Format.rate(disk.readRate, compact: true), !dynamic || reading))])
        }
    }

    private static func network(_ context: Context) -> MenubarSegment {
        guard let network = context.snapshot.network else { return compose(.network, [.text("NET", "—", template: "999K")]) }
        let dynamic = context.options.dynamicIcons
        let offline = network.interface == nil
        if offline && dynamic {
            return compose(.network, [.symbol("wifi.slash", size: 11), .text("NET", "OFF", template: "999K")])
        }
        let uploading = network.uploadRate > 2_000, downloading = network.downloadRate > 2_000
        switch context.options.networkStyle {
        case .stacked:
            return compose(.network, [
                .stacked(top: ("↑", Format.rate(network.uploadRate, compact: true), !dynamic || uploading),
                         bottom: ("↓", Format.rate(network.downloadRate, compact: true), !dynamic || downloading)),
            ])
        case .download:
            return compose(.network, [.text("↓ NET", Format.rate(network.downloadRate, compact: true), template: "999K",
                                            emphasized: dynamic && downloading)])
        case .total:
            let total = network.uploadRate + network.downloadRate
            return compose(.network, [.text("NET", Format.rate(total, compact: true), template: "999K",
                                            emphasized: dynamic && (uploading || downloading))])
        case .graphs, .graphsValues:
            let options = context.options
            let graph = Part.dualGraph(top: context.recent(.netUp, 20), bottom: context.recent(.netDown, 20),
                                       topColor: options.graphColor(.upload), bottomColor: options.graphColor(.download),
                                       floor: 20_000, width: options.networkStyle == .graphs ? 40 : 30)
            guard options.networkStyle == .graphsValues else { return compose(.network, [graph]) }
            return compose(.network, [graph, .stacked(top: ("↑", Format.rate(network.uploadRate, compact: true), !dynamic || uploading),
                                                      bottom: ("↓", Format.rate(network.downloadRate, compact: true), !dynamic || downloading))])
        }
    }

    private static func sensors(_ context: Context) -> MenubarSegment {
        let snapshot = context.snapshot
        let settings = context.options
        let (label, celsius): (String, Double?) = switch settings.sensorSource {
        case .cpuAverage: ("CPU", snapshot.cpuTemperature)
        case .cpuMax: ("MAX", snapshot.cpuTemperatureMax)
        case .hottest: ("TOP", snapshot.sensors.hottest?.celsius)
        case .ssd: ("SSD", snapshot.ssdTemperature)
        case .battery: ("BAT", snapshot.battery?.temperature ?? snapshot.sensors.batteryTemperature)
        }

        var symbol = "thermometer.medium"
        var hot = false
        if settings.dynamicIcons, let celsius {
            hot = celsius >= settings.temperatureHotThreshold
            symbol = celsius < 50 ? "thermometer.low" : (hot ? "thermometer.high" : "thermometer.medium")
            if snapshot.thermalState == .serious || snapshot.thermalState == .critical {
                symbol = "thermometer.sun.fill" // macOS is throttling for heat
                hot = true
            }
        }
        let value = celsius.map { Format.temperature($0, unit: false) } ?? "—"
        return compose(.sensors, [.symbol(symbol, size: 12), .text(label, value, template: "100°", emphasized: hot)])
    }

    private static func fans(_ context: Context) -> MenubarSegment {
        let fans = context.snapshot.smc?.fans ?? []
        let fastest = fans.max { $0.rpm < $1.rpm }
        let spinning = (fastest?.rpm ?? 0) > 0
        let angle = context.options.dynamicIcons && spinning ? context.fanAngle : 0
        let icon: Part = .fan(angle: angle, dimmed: context.options.dynamicIcons && !spinning)

        guard let fastest else { return compose(.fans, [icon, .text("FAN", "—", template: "6800")]) }
        switch context.options.fanStyle {
        case .rpm:
            return compose(.fans, [icon, .text("FAN", spinning ? String(format: "%.0f", fastest.rpm) : "OFF", template: "6800")])
        case .percent:
            return compose(.fans, [icon, .text("FAN", Format.percent(fastest.fraction), template: "100%")])
        case .iconOnly:
            return compose(.fans, [icon])
        }
    }

    private static func battery(_ context: Context) -> MenubarSegment {
        guard let battery = context.snapshot.battery else {
            return compose(.battery, [.symbol("powerplug.fill", size: 11)])
        }
        let dynamic = context.options.dynamicIcons
        let glyph: Part = .battery(level: battery.percent,
                                   charging: battery.isCharging,
                                   pluggedIn: battery.onACPower && !battery.isCharging,
                                   lowPower: dynamic && context.snapshot.lowPowerMode)
        let low = dynamic && !battery.onACPower && battery.percent <= 0.2

        let time = battery.minutesRemaining.map { Format.duration(minutes: $0) } ?? (battery.onACPower ? "AC" : "…")
        switch context.options.batteryStyle {
        case .percent:
            return compose(.battery, [glyph, .text("BAT", Format.percent(battery.percent), template: "100%", emphasized: low)])
        case .time:
            return compose(.battery, [glyph, .text(battery.isCharging ? "PIENO" : "RESTA", time, template: "10:00", emphasized: low)])
        case .percentTime:
            // Percentage above, time left (or to full, while charging) below; dimmed while the battery runs low.
            return compose(.battery, [glyph, .stacked(top: ("", Format.percent(battery.percent), !low),
                                                      bottom: ("", time, !low))])
        case .watts:
            let watts = battery.watts.map { String(format: "%.0fW", abs($0)) } ?? "—"
            return compose(.battery, [glyph, .text(battery.isCharging ? "IN" : "OUT", watts, template: "100W")])
        case .iconOnly:
            return compose(.battery, [glyph])
        case .insidePercent:
            return compose(.battery, [.batteryPercent(level: battery.percent,
                                                      charging: battery.isCharging,
                                                      pluggedIn: battery.onACPower && !battery.isCharging,
                                                      lowPower: dynamic && context.snapshot.lowPowerMode,
                                                      emphasized: low)])
        }
    }

    private static func date(_ context: Context) -> MenubarSegment {
        let options = context.options
        let now = context.now
        let time = options.use24Hour ? "HH:mm" : "h:mm"
        let seconds = options.use24Hour ? "HH:mm:ss" : "h:mm:ss"
        let suffix = options.use24Hour ? "" : " a"
        func format(_ pattern: String) -> String { DateText.string(now, pattern) }

        switch options.dateStyle {
        case .dayTime:
            let day = format("EEE d MMM")
            return compose(.date, [.plain(day + "  " + format(time + suffix), template: day + "  " + (options.use24Hour ? "88:88" : "88:88 MM"))])
        case .time:
            return compose(.date, [.plain(format(time + suffix), template: options.use24Hour ? "88:88" : "88:88 MM")])
        case .timeSeconds:
            return compose(.date, [.plain(format(seconds + suffix), template: options.use24Hour ? "88:88:88" : "88:88:88 MM")])
        case .stacked:
            return compose(.date, [.labeled(format("EEE d MMM").uppercased(), format(time + suffix),
                                            template: options.use24Hour ? "88:88" : "88:88 MM")])
        case .shortDate:
            return compose(.date, [.plain(format("EEE d MMM"), template: nil)])
        case .numeric:
            return compose(.date, [.plain(format("dd/MM/yy"), template: "88/88/88")])
        case .long:
            return compose(.date, [.plain(format("EEEE d MMMM"), template: nil)])
        case .calendarIcon:
            let page = Part.calendarPage(day: format("d"), weekday: weekdayShort(now))
            return compose(.date, [page, .plain(format("MMM").capitalized(with: DateText.locale), template: "Mmm")])
        case .calendarIconTime:
            let page = Part.calendarPage(day: format("d"), weekday: weekdayShort(now))
            return compose(.date, [page, .labeled(format("MMM").uppercased(), format(time + suffix),
                                                  template: options.use24Hour ? "88:88" : "88:88 MM")])
        }
    }

    /// "LUN", "MAR"… : three letters fit the calendar page's band.
    private static func weekdayShort(_ date: Date) -> String {
        String(DateText.string(date, "EEE").prefix(3)).uppercased()
    }

    private static func awake(_ context: Context) -> MenubarSegment {
        let state = context.awake
        let steams = state.isActive && context.options.dynamicIcons
        let symbol = Part.cup(active: state.isActive, steam: steams ? context.steamPhase : nil)
        // Kept narrow: timed sessions show the time left (or ∞), downloads their percentage when macOS reports one.
        // AI and app sessions show the cup alone: its steam already says it's on, and the dropdown says why.
        let time: String?
        let template: String?
        switch state.kind {
        case _ where !state.isActive: time = nil; template = nil
        case .timed:
            time = state.remaining(at: context.now).map(Format.clockCompact) ?? "∞"
            // Width for the hours actually shown, so "0:45" doesn't reserve room for "88:88".
            template = (time?.count ?? 0) > 4 ? "88:88" : "8:88"
        case .download(_, let progress): time = progress.map { Format.percent($0) }; template = "88%"
        case .app, .ai: time = nil; template = nil
        }
        switch context.options.awakeStyle {
        case .icon:
            return compose(.awake, [symbol])
        case .iconTime:
            guard let time else { return compose(.awake, [symbol]) }
            return compose(.awake, [symbol, .plain(time, template: template)])
        case .stacked:
            let status: String = {
                guard state.isActive else { return "SPENTO" }
                switch state.kind {
                case .ai: return "IA"
                case .app: return "APP"
                default: return "SVEGLIO"
                }
            }()
            return compose(.awake, [symbol, .labeled(status, time ?? (state.isActive ? "ON" : "—"), template: template ?? "88")])
        }
    }

    private static func weather(_ context: Context) -> MenubarSegment {
        guard let report = context.weather else {
            // Not configured yet (no place chosen) or still loading.
            let hint = context.weatherConfigured ? "…" : "—"
            return compose(.weather, [.symbol("cloud.sun", size: 12), .plain(hint, template: "88°")])
        }
        let symbol = Part.symbol(report.condition.menubarSymbol, size: 13)
        let temperature = Format.temperature(report.temperature, unit: false)
        switch context.options.weatherStyle {
        case .iconTemperature:
            return compose(.weather, [symbol, .plain(temperature, template: "-88°")])
        case .temperature:
            return compose(.weather, [.plain(temperature, template: "-88°")])
        case .iconOnly:
            return compose(.weather, [symbol])
        case .stacked:
            let city = report.location.name.count > 10 ? String(report.location.name.prefix(9)) + "…" : report.location.name
            return compose(.weather, [symbol, .labeled(city.uppercased(), temperature, template: "-88°")])
        }
    }

    // MARK: - Parts

    private enum Part {
        case text(String, String, template: String, emphasized: Bool = false)
        case stacked(top: (String, String, Bool), bottom: (String, String, Bool))
        case graph([Double], width: CGFloat = 16)
        case cores([Double])
        case ring(Double)
        case symbol(String, size: CGFloat)
        case fan(angle: CGFloat, dimmed: Bool)
        /// The Awake cup; with a `steam` phase, wisps rise from it.
        case cup(active: Bool, steam: CGFloat?)
        case battery(level: Double, charging: Bool, pluggedIn: Bool, lowPower: Bool)
        /// Always one line, whatever the labels setting. `template` fixes the width (nil: the text itself).
        case plain(String, template: String?)
        /// Always label above value.
        case labeled(String, String, template: String)
        /// Two graphs on one center line: `top` grows up from it, `bottom` down, each scaled to its own peak (at least
        /// `floor`, so idle noise stays flat). Colors nil: the module's accent.
        case dualGraph(top: [Double], bottom: [Double], topColor: NSColor?, bottomColor: NSColor?, floor: Double, width: CGFloat)
        /// A calendar page: the weekday cut out of its top band, the day number below.
        case calendarPage(day: String, weekday: String)
        /// A larger battery with the percentage written inside the fill.
        case batteryPercent(level: Double, charging: Bool, pluggedIn: Bool, lowPower: Bool, emphasized: Bool)
    }

    private static let partGap: CGFloat = 3
    /// Room for the bolt/plug drawn beside the percentage battery.
    /// Width of the bolt / vertical plug drawn to the left of the battery (never on top of it).
    private static let powerGlyphWidth: CGFloat = 7
    /// Set per segment from the context (rendering always happens on the main thread).
    private static var showLabels = true
    private static var ink = Ink(base: .black, accent: .black, value: .black)

    /// Colors for one segment.
    private struct Ink {
        /// Text and neutral marks (tracks, outlines).
        var base: NSColor
        /// The visual: icon, graph, ring, battery fill.
        var accent: NSColor
        /// The value text.
        var value: NSColor

        init(base: NSColor, accent: NSColor, value: NSColor) {
            self.base = base
            self.accent = accent
            self.value = value
        }

        init(module: ModuleID, options: MenubarOptions, severity: Severity) {
            // labelColor resolves when the image is drawn, in the menu bar's own appearance.
            base = options.usesColor ? .labelColor : .black
            accent = base
            value = base
            if options.colorIcons, let custom = options.moduleColors[module] { accent = custom }
            if options.severityColors, let alert = severity.nsColor {
                accent = alert
                if severity >= .high { value = alert }
            }
        }
    }

    private static func compose(_ module: ModuleID, _ parts: [Part]) -> MenubarSegment {
        // Captured now: the image draws lazily, after other segments may have changed the statics.
        let labels = Self.showLabels
        let ink = Self.ink
        let widths = parts.map { width(of: $0, showLabels: labels) }
        let total = widths.reduce(0, +) + partGap * CGFloat(max(parts.count - 1, 0))
        return MenubarSegment(module: module, width: ceil(total)) { rect in
            var x = rect.minX
            for (part, width) in zip(parts, widths) {
                draw(part, in: NSRect(x: x, y: rect.minY, width: width, height: rect.height), showLabels: labels, ink: ink)
                x += width + partGap
            }
        }
    }

    private static func width(of part: Part, showLabels: Bool) -> CGFloat {
        switch part {
        case .text(let label, _, let template, _):
            let valueWidth = measure(template, valueFont(showLabels))
            return showLabels ? max(valueWidth, measure(label, labelFont)) : valueWidth
        case .stacked(let top, let bottom):
            let valueWidth = max(measure("999K", stackFont), measure(top.1, stackFont), measure(bottom.1, stackFont))
            return max(measure(top.0, stackFont), measure(bottom.0, stackFont)) + 2 + valueWidth
        case .graph(_, let width): return width
        case .dualGraph(_, _, _, _, _, let width): return width
        case .cores(let cores): return CGFloat(max(cores.count, 1)) * 3
        case .ring: return 13
        case .symbol(_, let size): return size + 3
        case .fan: return 14
        case .cup: return 16
        case .calendarPage: return 18
        case .plain(let text, let template):
            return max(measure(text, plainFont), template.map { measure($0, plainFont) } ?? 0)
        case .labeled(let label, let value, let template):
            return max(measure(label, labelFont), measure(value, valueFont(true)), measure(template, valueFont(true)))
        case .battery(_, let charging, let pluggedIn, let lowPower):
            return ((charging || pluggedIn) ? powerGlyphWidth + 2 : 0) + 23.5 + (lowPower ? 12 : 0)
        case .batteryPercent(_, let charging, let pluggedIn, let lowPower, _):
            return ((charging || pluggedIn) ? powerGlyphWidth + 2 : 0) + 30.5 + (lowPower ? 12 : 0)
        }
    }

    private static func draw(_ part: Part, in rect: NSRect, showLabels: Bool, ink: Ink) {
        switch part {
        case .plain(let text, _):
            drawText(text, font: plainFont, color: ink.value, in: NSRect(x: rect.minX, y: 3.5, width: rect.width, height: 15))

        case .labeled(let label, let value, _):
            drawText(label, font: labelFont, color: ink.base.withAlphaComponent(0.6), in: NSRect(x: rect.minX, y: 11.5, width: rect.width, height: 9))
            drawText(value, font: valueFont(true), color: ink.value, in: NSRect(x: rect.minX, y: 0.5, width: rect.width, height: 12))

        case .text(let label, let value, _, let emphasized):
            if showLabels {
                drawText(label, font: labelFont, color: ink.base.withAlphaComponent(0.6), in: NSRect(x: rect.minX, y: 11.5, width: rect.width, height: 9))
                drawText(value, font: emphasized ? valueFontBold : valueFont(true), color: ink.value,
                         in: NSRect(x: rect.minX, y: 0.5, width: rect.width, height: 12))
            } else {
                drawText(value, font: emphasized ? NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .bold) : valueFont(false),
                         color: ink.value, in: NSRect(x: rect.minX, y: 3.5, width: rect.width, height: 15))
            }

        case .stacked(let top, let bottom):
            let prefixWidth = max(measure(top.0, stackFont), measure(bottom.0, stackFont))
            for (line, y) in [(top, 10.5), (bottom, 0.5)] as [((String, String, Bool), CGFloat)] {
                let color = line.2 ? ink.value : ink.base.withAlphaComponent(0.45)
                let prefix = line.2 ? ink.accent : color
                drawText(line.0, font: stackFont, color: prefix, in: NSRect(x: rect.minX, y: y, width: prefixWidth, height: 11))
                drawText(line.1, font: stackFont, color: color, in: NSRect(x: rect.minX + prefixWidth + 2, y: y,
                                                                         width: rect.width - prefixWidth - 2, height: 11), alignment: .right)
            }

        case .graph(let values, _):
            // Nearly full menu bar height.
            let plot = rect.insetBy(dx: 0.5, dy: 2.5)
            // Faint backdrop so the graph reads as a graph even at low load.
            ink.base.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: plot.insetBy(dx: -1, dy: -1), xRadius: 2, yRadius: 2).fill()
            ink.accent.setFill()
            let slots = max(Int(plot.width / 2), 1)
            for (index, value) in values.suffix(slots).enumerated() {
                let offset = slots - min(values.count, slots) + index
                let height = max(1, plot.height * CGFloat(min(max(value, 0), 1)))
                NSBezierPath(roundedRect: NSRect(x: plot.minX + CGFloat(offset) * 2, y: plot.minY, width: 1.5, height: height),
                             xRadius: 0.5, yRadius: 0.5).fill()
            }

        case .dualGraph(let top, let bottom, let topColor, let bottomColor, let floor, _):
            let plot = rect.insetBy(dx: 0.5, dy: 2)
            ink.base.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: plot.insetBy(dx: -1, dy: -0.5), xRadius: 2, yRadius: 2).fill()
            let middle = plot.midY
            let half = plot.height / 2 - 0.75
            let slots = max(Int(plot.width / 2), 1)
            func bars(_ values: [Double], color: NSColor, upward: Bool) {
                let shown = Array(values.suffix(slots))
                let peak = max(shown.max() ?? 0, floor)
                color.setFill()
                for (index, value) in shown.enumerated() {
                    let offset = slots - shown.count + index
                    let height = max(0.75, half * CGFloat(min(max(value / peak, 0), 1)))
                    let y = upward ? middle + 0.75 : middle - 0.75 - height
                    NSBezierPath(roundedRect: NSRect(x: plot.minX + CGFloat(offset) * 2, y: y, width: 1.5, height: height),
                                 xRadius: 0.5, yRadius: 0.5).fill()
                }
            }
            bars(top, color: topColor ?? ink.accent, upward: true)
            bars(bottom, color: bottomColor ?? ink.accent, upward: false)
            ink.base.withAlphaComponent(0.25).setFill()
            NSRect(x: plot.minX, y: middle - 0.25, width: plot.width, height: 0.5).fill()

        case .cores(let cores):
            let plot = rect.insetBy(dx: 0, dy: 3)
            for (index, value) in cores.enumerated() {
                let bar = NSRect(x: plot.minX + CGFloat(index) * 3, y: plot.minY, width: 2, height: plot.height)
                ink.base.withAlphaComponent(0.2).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
                ink.accent.setFill()
                var filled = bar
                filled.size.height = max(1.5, plot.height * CGFloat(min(max(value, 0), 1)))
                NSBezierPath(roundedRect: filled, xRadius: 1, yRadius: 1).fill()
            }

        case .ring(let fraction):
            let circle = NSRect(x: rect.midX - 6, y: rect.midY - 6, width: 12, height: 12).insetBy(dx: 1.25, dy: 1.25)
            let track = NSBezierPath(ovalIn: circle)
            track.lineWidth = 2.5
            ink.base.withAlphaComponent(0.25).setStroke()
            track.stroke()
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: circle.midX, y: circle.midY), radius: circle.width / 2,
                          startAngle: 90, endAngle: 90 - 360 * CGFloat(min(max(fraction, 0), 1)), clockwise: true)
            arc.lineWidth = 2.5
            arc.lineCapStyle = .round
            ink.accent.setStroke()
            arc.stroke()

        case .symbol(let name, let size):
            drawSymbol(name, size: size, in: rect, color: ink.accent)

        case .fan(let angle, let dimmed):
            guard let symbol = symbolImage("fan", size: 12) else { return }
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byRadians: angle)
            transform.concat()
            let target = NSRect(x: -symbol.size.width / 2, y: -symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height)
            tinted(symbol, ink.accent).draw(in: target, from: .zero, operation: .sourceOver, fraction: dimmed ? 0.5 : 1)
            NSGraphicsContext.restoreGraphicsState()

        case .cup(let active, let steam):
            // Same size as the other icons. With steam the cup sits a little low, so the wisps fit in the 22 pt bar.
            let cup = NSRect(x: rect.minX, y: rect.minY - (steam == nil ? 0 : 2), width: rect.width, height: rect.height)
            drawSymbol(active ? "cup.and.saucer.fill" : "cup.and.saucer", size: 13, in: cup, color: ink.accent)
            if let steam { drawSteam(phase: steam, in: rect, color: ink.accent) }

        case .calendarPage(let day, let weekday):
            let page = NSRect(x: rect.minX + 0.75, y: rect.minY + 2, width: 16.5, height: 18)
            let band = NSRect(x: page.minX, y: page.maxY - 6.5, width: page.width, height: 6.5)
            // Outline of the page, then the band filled with the accent, rounded like the page's top corners.
            let outline = NSBezierPath(roundedRect: page.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.5, yRadius: 3.5)
            outline.lineWidth = 1
            ink.base.withAlphaComponent(0.85).setStroke()
            outline.stroke()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: page, xRadius: 3.5, yRadius: 3.5).addClip()
            ink.accent.setFill()
            band.fill()
            NSGraphicsContext.restoreGraphicsState()
            if let context = NSGraphicsContext.current {
                let font = NSFont.systemFont(ofSize: 5.2, weight: .heavy)
                let text = weekday as NSString
                let size = text.size(withAttributes: [.font: font, .kern: 0.3])
                context.saveGraphicsState()
                context.compositingOperation = .destinationOut
                text.draw(at: NSPoint(x: band.midX - size.width / 2, y: band.midY - size.height / 2 + 0.2),
                          withAttributes: [.font: font, .kern: 0.3, .foregroundColor: NSColor.black])
                context.restoreGraphicsState()
            }
            let number = day as NSString
            let numberFont = roundedFont(size: 10, weight: .bold)
            let numberSize = number.size(withAttributes: [.font: numberFont])
            let body = NSRect(x: page.minX, y: page.minY, width: page.width, height: page.height - band.height)
            number.draw(at: NSPoint(x: body.midX - numberSize.width / 2, y: body.midY - numberSize.height / 2 + 0.3),
                        withAttributes: [.font: numberFont, .foregroundColor: ink.value])

        case .battery(let level, let charging, let pluggedIn, let lowPower):
            let body = batteryBody(in: rect, charging: charging, pluggedIn: pluggedIn, width: 20, height: 10, radius: 3, ink: ink)
            let inner = body.insetBy(dx: 1.75, dy: 1.75)
            var fill = inner
            fill.size.width = max(1.5, inner.width * CGFloat(min(max(level, 0), 1)))
            ink.accent.setFill()
            NSBezierPath(roundedRect: fill, xRadius: 1.25, yRadius: 1.25).fill()
            if lowPower {
                drawSymbol("leaf.fill", size: 8, in: NSRect(x: body.maxX + 5, y: rect.minY, width: 9, height: rect.height), color: ink.base)
            }

        case .batteryPercent(let level, let charging, let pluggedIn, let lowPower, let emphasized):
            let body = batteryBody(in: rect, charging: charging, pluggedIn: pluggedIn, width: 27, height: 13, radius: 4, ink: ink)
            // iOS-style: a translucent track for the empty part, the level in solid color, and the digits cut out
            // of the whole body, so they never split in two colors at the fill's edge.
            let inner = body.insetBy(dx: 1.75, dy: 1.75)
            ink.base.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: inner, xRadius: 2.25, yRadius: 2.25).fill()
            var fill = inner
            fill.size.width = max(2, inner.width * CGFloat(min(max(level, 0), 1)))
            ink.accent.setFill()
            NSBezierPath(roundedRect: fill, xRadius: 2.25, yRadius: 2.25).fill()

            let text = String(Int((level * 100).rounded())) as NSString
            let font = roundedFont(size: 10, weight: emphasized ? .heavy : .bold)
            let size = text.size(withAttributes: [.font: font])
            let origin = NSPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2 + 0.25)
            guard let context = NSGraphicsContext.current else { break }
            context.saveGraphicsState()
            context.compositingOperation = .destinationOut
            text.draw(at: origin, withAttributes: [.font: font, .foregroundColor: NSColor.black])
            context.restoreGraphicsState()

            if lowPower {
                drawSymbol("leaf.fill", size: 8, in: NSRect(x: body.maxX + 5, y: rect.minY, width: 9, height: rect.height), color: ink.base)
            }
        }
    }

    /// Draws the bolt (charging) or a vertical plug (plugged in, not charging) left of the battery, then the
    /// battery outline and nub. Returns the body rectangle for the fill.
    private static func batteryBody(in rect: NSRect, charging: Bool, pluggedIn: Bool, width: CGFloat, height: CGFloat,
                                    radius: CGFloat, ink: Ink) -> NSRect {
        var x = rect.minX
        if charging || pluggedIn {
            let glyph = NSRect(x: x, y: rect.minY, width: powerGlyphWidth, height: rect.height)
            if charging {
                drawSymbol("bolt.fill", size: 9, in: glyph, color: ink.base)
            } else {
                drawVerticalPlug(in: glyph, color: ink.base)
            }
            x += powerGlyphWidth + 2
        }
        let body = NSRect(x: x + 0.5, y: (rect.midY - height / 2).rounded() + 0.5, width: width, height: height)
        let outline = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
        outline.lineWidth = 1
        ink.base.withAlphaComponent(0.5).setStroke()
        outline.stroke()
        ink.base.withAlphaComponent(0.5).setFill()
        let nubHeight = (height * 0.38).rounded()
        NSBezierPath(roundedRect: NSRect(x: body.maxX + 1, y: body.midY - nubHeight / 2, width: 1.75, height: nubHeight),
                     xRadius: 0.875, yRadius: 0.875).fill()
        return body
    }

    /// A small upright plug (two prongs, body, cable), crisp at menu bar size where the SF Symbol is too wide.
    private static func drawVerticalPlug(in rect: NSRect, color: NSColor) {
        let width: CGFloat = 6, height: CGFloat = 12
        let x = (rect.midX - width / 2).rounded(), y = (rect.midY - height / 2).rounded()
        color.setFill()
        for prong in [x + 1, x + width - 2.25] {
            NSBezierPath(roundedRect: NSRect(x: prong, y: y + height - 3.25, width: 1.25, height: 3.25), xRadius: 0.6, yRadius: 0.6).fill()
        }
        NSBezierPath(roundedRect: NSRect(x: x, y: y + 3.5, width: width, height: 5.5), xRadius: 1.75, yRadius: 1.75).fill()
        NSBezierPath(roundedRect: NSRect(x: rect.midX - 0.75, y: y, width: 1.5, height: 4.5), xRadius: 0.75, yRadius: 0.75).fill()
    }

    private static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    // MARK: - Text and symbols

    private static let labelFont = NSFont.systemFont(ofSize: 7.5, weight: .bold)
    private static let plainFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
    private static let stackFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
    private static let valueFontBold = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .heavy)

    private static func valueFont(_ withLabel: Bool) -> NSFont {
        withLabel ? .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold) : .monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
    }

    private static func measure(_ text: String, _ font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func drawText(_ text: String, font: NSFont, color: NSColor, in rect: NSRect, alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byClipping
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    }

    private static var symbolCache: [String: NSImage] = [:]

    private static func symbolImage(_ name: String, size: CGFloat) -> NSImage? {
        let key = "\(name)@\(size)"
        if let cached = symbolCache[key] { return cached }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .semibold))
        symbolCache[key] = image
        return image
    }

    /// SF Symbols are black masks; paint them in `color` (drawn now, so dynamic colors resolve in the menu bar's appearance).
    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        if color == .black { return image }
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        result.unlockFocus()
        return result
    }

    /// Three wavy wisps over the cup. Each is a sine curve whose wave scrolls upward with `phase`, and fades out
    /// toward its tip, so the steam seems to rise and thin out.
    private static func drawSteam(phase: CGFloat, in rect: NSRect, color: NSColor) {
        let baseY = rect.midY + 3.6 // top of the cup
        let height: CGFloat = 7
        let step: CGFloat = 0.5
        let wisps: [(x: CGFloat, offset: CGFloat, scale: CGFloat)] = [(-3, 0, 0.85), (0, 2.1, 1), (3, 4.2, 0.75)]
        for wisp in wisps {
            var y: CGFloat = 0
            var previous: NSPoint?
            while y <= height {
                let t = y / height
                let wave = sin(y * 0.75 - phase * 2 * .pi + wisp.offset)
                let point = NSPoint(x: rect.midX + wisp.x + wave * 0.8 * wisp.scale * (0.6 + 0.4 * t), y: baseY + y * wisp.scale)
                if let previous {
                    let alpha = pow(1 - t, 1.1) * 0.9
                    let segment = NSBezierPath()
                    segment.move(to: previous)
                    segment.line(to: point)
                    segment.lineWidth = 1
                    segment.lineCapStyle = .round
                    color.withAlphaComponent(alpha).setStroke()
                    segment.stroke()
                }
                previous = point
                y += step
            }
        }
    }

    private static func drawSymbol(_ name: String, size: CGFloat, in rect: NSRect, color: NSColor) {
        guard let image = symbolImage(name, size: size) else { return }
        let target = NSRect(x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2,
                            width: image.size.width, height: image.size.height)
        tinted(image, color).draw(in: target)
    }

    /// Flattens a menu bar image for a light or dark bar (template images are tinted, colored ones resolve their colors).
    static func rasterize(_ image: NSImage, dark: Bool, scale: CGFloat = 2) -> NSImage {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let size = image.size
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        appearance.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(origin: .zero, size: size))
            if image.isTemplate {
                (dark ? NSColor.white : NSColor.black).set()
                NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: size)
        result.addRepresentation(bitmap)
        return result
    }
}

/// Value snapshot of the settings the renderer needs, so previews can render any style.
struct MenubarOptions {
    var showLabels: Bool
    var dynamicIcons: Bool
    var severityColors: Bool
    var colorIcons: Bool
    var moduleColors: [ModuleID: NSColor]
    var cpuStyle: CPUStyle
    var memoryStyle: MemoryStyle
    var diskStyle: DiskStyle
    var networkStyle: NetworkStyle
    var sensorSource: SensorSource
    var fanStyle: FanStyle
    var batteryStyle: BatteryStyle
    var dateStyle: DateStyle
    var use24Hour: Bool
    var weatherStyle: WeatherStyle
    var awakeStyle: AwakeStyle
    var cpuBusyThreshold: Double
    var temperatureHotThreshold: Double
    var graphColors: Bool
    var graphSeriesColors: [GraphSeries: NSColor]
    /// Draw a colored (non-template) image whatever the settings: the calendar announcement needs it.
    var forceColor = false

    /// Colored network and disk graphs need a colored image too.
    var usesColor: Bool {
        forceColor || severityColors || colorIcons || (graphColors && (networkStyle.usesGraphs || diskStyle.usesGraphs))
    }

    func graphColor(_ series: GraphSeries) -> NSColor? { graphColors ? graphSeriesColors[series] : nil }

    init(_ settings: Settings) {
        showLabels = settings.showLabels
        dynamicIcons = settings.dynamicIcons
        severityColors = settings.severityColors
        colorIcons = settings.colorIcons
        moduleColors = Dictionary(uniqueKeysWithValues: ModuleID.allCases.map { ($0, settings.color(for: $0)) })
        cpuStyle = settings.cpuStyle
        memoryStyle = settings.memoryStyle
        diskStyle = settings.diskStyle
        networkStyle = settings.networkStyle
        sensorSource = settings.sensorSource
        fanStyle = settings.fanStyle
        batteryStyle = settings.batteryStyle
        dateStyle = settings.dateStyle
        use24Hour = settings.use24Hour
        weatherStyle = settings.weatherStyle
        awakeStyle = settings.awakeStyle
        cpuBusyThreshold = settings.cpuBusyThreshold
        temperatureHotThreshold = settings.temperatureHotThreshold
        graphColors = settings.graphColors
        graphSeriesColors = Dictionary(uniqueKeysWithValues: GraphSeries.allCases.map { ($0, settings.color(for: $0)) })
    }
}

/// Italian date formatting with cached formatters (patterns are fixed, so one formatter each).
enum DateText {
    static let locale = Locale(identifier: "it_IT")
    private static var cache: [String: DateFormatter] = [:]

    static func string(_ date: Date, _ pattern: String) -> String {
        if let formatter = cache[pattern] { return formatter.string(from: date) }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = pattern
        cache[pattern] = formatter
        return formatter.string(from: date)
    }
}
