import AppKit
import MenuStatsWidgetUI
import SwiftUI

/// Offscreen renders of the UI for visual checks (`--render-ui`): menu bar styles, dashboard tabs, settings pages.
enum UITestRenderer {
    static func renderAll(model: AppModel, to directory: URL) {
        let settings = model.settings
        ProcessReader.hideOwnProcess = true
        // Real weather for the previews (one Open-Meteo request, test only; user settings untouched).
        model.weather.configure(enabled: true, location: WeatherLocation(name: "Roma", region: "Lazio", country: "Italia",
                                                                          latitude: 41.8919, longitude: 12.5113))
        let deadline = Date().addingTimeInterval(8)
        while model.weather.report == nil, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        renderMenubar(model: model, settings: settings, to: directory.appendingPathComponent("menubar.png"))
        renderBatteryStates(model: model, settings: settings, to: directory.appendingPathComponent("battery-states.png"))
        for dark in [true, false] {
            renderMenubarHero(model: model, settings: settings, dark: dark,
                              to: directory.appendingPathComponent(dark ? "hero-menubar-dark.png" : "hero-menubar-light.png"))
        }

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for tab in DashboardTab.allCases {
                // Sample as the real dropdown would for this tab (processes, volumes, all sensors).
                model.setVisibleTab(tab)
                Thread.sleep(forTimeInterval: 1.1)
                model.tick()
                let state = DashboardState()
                state.tab = tab
                let view = DashboardView(model: model, state: state, maxContentHeight: 2000, openSettings: {}, quit: {})
                    .background(VisualEffectBackground())
                save(view, appearance: appearance, to: directory.appendingPathComponent("panel-\(tab.rawValue)-\(name).png"))
                model.setNetworkProcessSampling(false) // offscreen views never disappear, so stop nettop here
            }
        }
        for dark in [true, false] {
            renderWidgetGallery(model: model, dark: dark, to: directory.appendingPathComponent("widgets-\(dark ? "dark" : "light").png"))
        }
        let pages: [(String, AnyView)] = [
            ("widgets", AnyView(WidgetSettings(model: model))),
            ("updates", AnyView(UpdateSettings(updater: model.updater))),
            ("general", AnyView(GeneralSettings(settings: settings, model: model, snapshot: model.snapshot))),
            ("menubar", AnyView(MenubarSettings(model: model, snapshot: model.snapshot, settings: settings))),
            ("cpu", AnyView(ModuleSettings(module: .cpu, model: model, snapshot: model.snapshot, settings: settings))),
            ("network", AnyView(ModuleSettings(module: .network, model: model, snapshot: model.snapshot, settings: settings))),
            ("fans", AnyView(ModuleSettings(module: .fans, model: model, snapshot: model.snapshot, settings: settings))),
            ("awake", AnyView(ModuleSettings(module: .awake, model: model, snapshot: model.snapshot, settings: settings))),
            ("map", AnyView(MapSettings(settings: settings))),
            ("notifications", AnyView(NotificationSettings(settings: settings))),
        ]
        for (name, page) in pages {
            save(page.padding(22).frame(width: 640).background(Color(nsColor: .windowBackgroundColor)), appearance: .aqua,
                 to: directory.appendingPathComponent("settings-\(name).png"))
        }
    }

    /// Every desktop widget (each element, each size) at its real macOS size on a wallpaper-like gradient.
    private static func renderWidgetGallery(model: AppModel, dark: Bool, to url: URL) {
        model.setVisibleTab(nil)
        model.tick()
        let data = model.widgetData(forceWeather: true)
        func tile(_ element: WidgetElement, _ size: WidgetSize) -> some View {
            WidgetPreviewTile(element: element, size: size, data: data)
        }
        let elements = WidgetElement.allCases
        let view = HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(elements.prefix(3)) { element in HStack(spacing: 24) { tile(element, .small); tile(element, .medium) } }
            }
            VStack(alignment: .leading, spacing: 24) {
                ForEach(elements.dropFirst(3)) { element in HStack(spacing: 24) { tile(element, .small); tile(element, .medium) } }
            }
        }
        .padding(40)
        .background(LinearGradient(colors: dark ? [Color(red: 0.10, green: 0.12, blue: 0.25), Color(red: 0.30, green: 0.12, blue: 0.32)]
                                                : [Color(red: 0.55, green: 0.72, blue: 0.95), Color(red: 0.95, green: 0.75, blue: 0.80)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        save(view, appearance: dark ? .darkAqua : .aqua, to: url)
    }

    /// Every module in every style, on a light and a dark menu bar strip.
    /// README hero: the full menu bar (every module, default styles) at 3x on a wallpaper-like gradient.
    private static func renderMenubarHero(model: AppModel, settings: Settings, dark: Bool, to url: URL) {
        var options = MenubarOptions(settings)
        options.showLabels = true
        options.dateStyle = .dayTime
        // A render only collects a few samples, so the CPU mini graph gets a representative history.
        let history: [Double] = [0.18, 0.22, 0.35, 0.28, 0.41, 0.33, 0.26, 0.52, 0.47, 0.30, 0.24, 0.38, 0.45, 0.29, 0.36]
        let context = MenubarRenderer.Context(snapshot: model.snapshot, options: options,
                                              recent: { metric, count in metric == .cpu ? Array(history.suffix(count)) : model.recentValues(metric, count: count) },
                                              fanAngle: 0.5, weather: model.weather.report, weatherConfigured: true)
        let modules: [ModuleID] = [.cpu, .memory, .disk, .network, .sensors, .fans, .battery, .weather, .date, .awake]
        let bar = MenubarRenderer.image(for: modules, context: context).image
        let scale: CGFloat = 3
        let barSize = NSSize(width: bar.size.width * scale, height: bar.size.height * scale)
        let size = NSSize(width: barSize.width + 120, height: barSize.height + 60)
        let canvas = NSImage(size: size, flipped: false) { rect in
            let colors = dark ? [NSColor(srgbRed: 0.10, green: 0.11, blue: 0.24, alpha: 1), NSColor(srgbRed: 0.29, green: 0.16, blue: 0.40, alpha: 1)]
                              : [NSColor(srgbRed: 0.80, green: 0.87, blue: 0.98, alpha: 1), NSColor(srgbRed: 0.96, green: 0.86, blue: 0.93, alpha: 1)]
            NSGradient(colors: colors)?.draw(in: NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28), angle: 0)
            let strip = NSRect(x: 30, y: 20, width: size.width - 60, height: barSize.height + 20)
            (dark ? NSColor(white: 0, alpha: 0.35) : NSColor(white: 1, alpha: 0.55)).setFill()
            NSBezierPath(roundedRect: strip, xRadius: 18, yRadius: 18).fill()
            let flat = MenubarRenderer.rasterize(bar, dark: dark, scale: scale)
            flat.draw(in: NSRect(x: (size.width - barSize.width) / 2, y: 30, width: barSize.width, height: barSize.height))
            return true
        }
        write(canvas, to: url)
    }

    /// Every battery style in every power state (simulated), at 4x, on light and dark strips.
    private static func renderBatteryStates(model: AppModel, settings: Settings, to url: URL) {
        let states: [(String, BatteryStats, Bool)] = [
            ("In carica 45%", BatteryStats(percent: 0.45, isCharging: true, onACPower: true, minutesRemaining: 50), false),
            ("Collegata 100%", BatteryStats(percent: 1, isCharging: false, onACPower: true, minutesRemaining: nil), false),
            ("A batteria 72%", BatteryStats(percent: 0.72, isCharging: false, onACPower: false, minutesRemaining: 300), false),
            ("Scarica 12%", BatteryStats(percent: 0.12, isCharging: false, onACPower: false, minutesRemaining: 30), false),
            ("Basso consumo 58%", BatteryStats(percent: 0.58, isCharging: false, onACPower: false, minutesRemaining: 200), true),
        ]
        let styles: [BatteryStyle] = [.percent, .insidePercent, .iconOnly]
        var images: [(String, NSImage)] = []
        for style in styles {
            for (title, battery, lowPower) in states {
                var snapshot = model.snapshot
                snapshot.battery = battery
                snapshot.lowPowerMode = lowPower
                var options = MenubarOptions(settings)
                options.batteryStyle = style
                options.dynamicIcons = true
                let context = MenubarRenderer.Context(snapshot: snapshot, options: options, recent: { _, _ in [] })
                images.append(("\(style.label) · \(title)", MenubarRenderer.image(for: [.battery], context: context).image))
            }
        }
        let scale: CGFloat = 4, rowHeight: CGFloat = 26 * scale, labelWidth: CGFloat = 300
        let stripWidth = (images.map(\.1.size.width).max() ?? 40) * scale + 40
        let size = NSSize(width: labelWidth + stripWidth * 2 + 30, height: CGFloat(images.count) * (rowHeight + 8) + 10)
        let canvas = NSImage(size: size, flipped: true) { _ in
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            for (index, row) in images.enumerated() {
                let y = 5 + CGFloat(index) * (rowHeight + 8)
                (row.0 as NSString).draw(at: NSPoint(x: 8, y: y + rowHeight / 2 - 8), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
                for (column, dark) in [false, true].enumerated() {
                    let strip = NSRect(x: labelWidth + CGFloat(column) * (stripWidth + 10), y: y, width: stripWidth, height: rowHeight)
                    (dark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
                    NSBezierPath(roundedRect: strip, xRadius: 10, yRadius: 10).fill()
                    let flat = MenubarRenderer.rasterize(row.1, dark: dark, scale: scale)
                    flat.draw(in: NSRect(x: strip.minX + 20, y: strip.minY + (rowHeight - row.1.size.height * scale) / 2,
                                         width: row.1.size.width * scale, height: row.1.size.height * scale),
                              from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
                }
            }
            return true
        }
        write(canvas, to: url)
    }

    private static func renderMenubar(model: AppModel, settings: Settings, to url: URL) {
        var rows: [(String, NSImage)] = []
        let base = MenubarOptions(settings)
        func add(_ title: String, _ modules: [ModuleID], _ change: (inout MenubarOptions) -> Void = { _ in }) {
            var options = base
            change(&options)
            let context = MenubarRenderer.Context(snapshot: model.snapshot, options: options,
                                                  recent: { model.recentValues($0, count: $1) }, fanAngle: 0.6,
                                                  weather: model.weather.report, weatherConfigured: true)
            rows.append((title, MenubarRenderer.image(for: modules, context: context).image))
        }
        add("Combinata (default)", settings.visibleModules + [.battery])
        add("Combinata senza etichette", settings.visibleModules + [.battery]) { $0.showLabels = false }
        for style in CPUStyle.allCases { add("CPU: \(style.label)", [.cpu]) { $0.cpuStyle = style } }
        for style in MemoryStyle.allCases { add("Memoria: \(style.label)", [.memory]) { $0.memoryStyle = style } }
        for style in DiskStyle.allCases { add("Disco: \(style.label)", [.disk]) { $0.diskStyle = style } }
        for style in NetworkStyle.allCases { add("Rete: \(style.label)", [.network]) { $0.networkStyle = style } }
        for source in SensorSource.allCases { add("Temp: \(source.label)", [.sensors]) { $0.sensorSource = source } }
        for style in FanStyle.allCases { add("Ventole: \(style.label)", [.fans]) { $0.fanStyle = style } }
        for style in BatteryStyle.allCases { add("Batteria: \(style.label)", [.battery]) { $0.batteryStyle = style } }
        for style in DateStyle.allCases { add("Data: \(style.label)", [.date]) { $0.dateStyle = style } }
        add("Data: Giorno e ora (12 ore)", [.date]) { $0.dateStyle = .dayTime; $0.use24Hour = false }
        for style in WeatherStyle.allCases { add("Meteo: \(style.label)", [.weather]) { $0.weatherStyle = style } }
        for style in AwakeStyle.allCases { add("Sveglio: \(style.label)", [.awake]) { $0.awakeStyle = style } }
        // The cup's steam at six points of its cycle, plus the idle (outline) cup.
        for phase in stride(from: 0.0, to: 1.0, by: 1.0 / 6) {
            let context = MenubarRenderer.Context(snapshot: model.snapshot, options: base, recent: { model.recentValues($0, count: $1) },
                                                  steamPhase: CGFloat(phase), awake: .sample)
            rows.append((String(format: "Sveglio: vapore fase %.2f", phase), MenubarRenderer.image(for: [.awake], context: context).image))
        }
        add("Sveglio: spento", [.awake])
        let withSteam = MenubarRenderer.Context(snapshot: model.snapshot, options: base, recent: { model.recentValues($0, count: $1) },
                                                fanAngle: 0.6, steamPhase: 0.3, weather: model.weather.report,
                                                weatherConfigured: true, awake: .sample)
        rows.append(("Sveglio accanto alle altre icone", MenubarRenderer.image(for: [.fans, .battery, .awake, .weather], context: withSteam).image))
        add("Combinata con meteo e data", settings.visibleModules + [.weather, .date])
        add("Icone dinamiche: CPU sotto carico", [.cpu, .sensors]) { $0.cpuBusyThreshold = 0; $0.temperatureHotThreshold = 0 }
        add("Allerta: attenzione (giallo)", [.cpu, .sensors]) { $0.severityColors = true; $0.cpuBusyThreshold = 0.25; $0.temperatureHotThreshold = 45 }
        add("Allerta: alto (arancione)", [.cpu, .sensors]) { $0.severityColors = true; $0.cpuBusyThreshold = 0.05; $0.temperatureHotThreshold = 35 }
        add("Allerta: critico (rosso)", [.cpu, .sensors]) { $0.severityColors = true; $0.cpuBusyThreshold = 0.0; $0.temperatureHotThreshold = 20 }
        add("Colori per modulo", settings.visibleModules + [.battery]) { $0.colorIcons = true; $0.severityColors = false }
        add("Colori per modulo + allerte", settings.visibleModules + [.battery]) { $0.colorIcons = true; $0.severityColors = true }
        add("Monocromatica (allerte spente)", settings.visibleModules + [.battery]) { $0.colorIcons = false; $0.severityColors = false }

        let rowHeight: CGFloat = 30, labelWidth: CGFloat = 230
        let stripWidth = (rows.map(\.1.size.width).max() ?? 100) + 24
        let size = NSSize(width: labelWidth + stripWidth * 2 + 20, height: CGFloat(rows.count) * rowHeight + 10)
        let canvas = NSImage(size: size, flipped: true) { _ in
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            for (index, row) in rows.enumerated() {
                let y = 5 + CGFloat(index) * rowHeight
                (row.0 as NSString).draw(at: NSPoint(x: 8, y: y + 7), withAttributes: [.font: NSFont.systemFont(ofSize: 11)])
                for (column, dark) in [false, true].enumerated() {
                    let strip = NSRect(x: labelWidth + CGFloat(column) * (stripWidth + 10), y: y + 2, width: stripWidth, height: 26)
                    (dark ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
                    NSBezierPath(roundedRect: strip, xRadius: 5, yRadius: 5).fill()
                    let tinted = MenubarRenderer.rasterize(row.1, dark: dark)
                    tinted.draw(in: NSRect(x: strip.minX + 12, y: strip.minY + 2, width: row.1.size.width, height: row.1.size.height),
                                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
            return true
        }
        write(canvas, to: url)
    }

    private static func tint(_ image: NSImage, color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private static func save<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3)) // let SwiftUI and Charts finish layout
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func write(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return }
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Opaque stand-in for the panel's blur, used only in offscreen renders.
private struct VisualEffectBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { scheme == .dark ? Color(white: 0.17) : Color(white: 0.95) }
}
