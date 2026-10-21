import AppKit
import Combine

/// Owns the status items: one combined item (compact) or one per module, re-rendered on every
/// sample and on settings changes. A left click opens the dashboard on the clicked module's tab.
final class StatusBarController: NSObject {
    private let model: AppModel
    private let settings: Settings
    private let panel: DashboardPanelController
    private let openSettings: () -> Void

    private struct Entry {
        var item: NSStatusItem
        var modules: [ModuleID]
        var hitRanges: [(ModuleID, ClosedRange<CGFloat>)] = []
        var imageWidth: CGFloat = 0
        /// Pixels of the image currently shown, to skip identical updates.
        var pixels = Data()
        /// Appearance the shown bitmap was rasterized for; a light/dark switch forces a new one on the next render.
        var appearanceName: NSAppearance.Name?
    }

    private var entries: [Entry] = []
    private var cancellables: Set<AnyCancellable> = []
    private var fanAngle: CGFloat = 0
    private var steamPhase: CGFloat = 0
    private var animationTimer: Timer?

    init(model: AppModel, panel: DashboardPanelController, openSettings: @escaping () -> Void) {
        self.model = model
        self.settings = model.settings
        self.panel = panel
        self.openSettings = openSettings
        super.init()
        lastGeometry = Self.savedGeometry()
        observeRoom()

        model.$snapshot.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.render()
            self?.updateAnimation()
        }.store(in: &cancellables)

        // objectWillChange fires before the new value is stored; rebuild on the next run loop pass.
        settings.objectWillChange.debounce(for: .milliseconds(30), scheduler: RunLoop.main).sink { [weak self] _ in
            self?.fitLevel = 0 // rebuild() picks the step that fits again
            self?.rebuild()
        }.store(in: &cancellables)

        // A new weather report re-renders the bar (every 15 minutes at most).
        model.weather.$report.receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }.store(in: &cancellables)

        // Starting or ending an Awake session updates the bar at once, not at the next sample.
        model.awake.$state.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.render()
            self?.updateAnimation()
        }.store(in: &cancellables)

        rebuild()
    }

    /// One-second clock, only while the date module shows seconds (otherwise the 2 s sample is enough).
    private var clockTimer: Timer?

    private func updateClock() {
        let needsSeconds = settings.isEnabled(.date) && settings.dateStyle == .timeSeconds
        if needsSeconds, clockTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.render() }
            timer.tolerance = 0.05
            RunLoop.main.add(timer, forMode: .common)
            clockTimer = timer
        } else if !needsSeconds, let timer = clockTimer {
            timer.invalidate()
            clockTimer = nil
        }
    }

    /// The modules as configured (with the compact bar's limit), before any automatic fit.
    private var configuredModules: [ModuleID] {
        let modules = settings.visibleModules
        return settings.compactMenubar ? Array(modules.prefix(max(settings.compactModuleCount, 1))) : modules
    }

    private var configuredLabels: Bool { settings.showLabels && !settings.compactMenubar }

    private var structure: [[ModuleID]] {
        var modules = configuredModules
        if settings.autoFitMenubar { modules = Array(modules.prefix(max(currentStep.moduleCount, 1))) }
        return settings.layout == .combined ? [modules] : modules.map { [$0] }
    }

    // MARK: - Room in the menu bar

    /// The step of `ladder` shown (0 = as configured). See MenubarFit for the order of the steps.
    private var fitLevel = 0
    private var ladder: [(step: MenubarFit.Step, width: CGFloat)] = []
    private var ladderTime = -Double.infinity
    /// Right edge of MenuStats' items and the notch's right edge on that display, from the last time they were
    /// visible: the room can still be computed while macOS keeps the items hidden.
    private var lastGeometry: (rightEdge: CGFloat, notchRightEdge: CGFloat?)? {
        didSet { if let lastGeometry, lastGeometry.rightEdge != oldValue?.rightEdge { Self.saveGeometry(lastGeometry) } }
    }

    /// The geometry is kept across launches (for the same display width), so MenuStats starts at the right step
    /// instead of appearing too wide and being hidden by macOS first.
    private static let geometryKey = "menubarFitGeometry"

    private static func saveGeometry(_ geometry: (rightEdge: CGFloat, notchRightEdge: CGFloat?)) {
        guard let notch = geometry.notchRightEdge, let width = NSScreen.main?.frame.width else { return }
        UserDefaults.standard.set([Double(geometry.rightEdge), Double(notch), Double(width)], forKey: geometryKey)
    }

    private static func savedGeometry() -> (rightEdge: CGFloat, notchRightEdge: CGFloat?)? {
        guard let values = UserDefaults.standard.array(forKey: geometryKey) as? [Double], values.count == 3,
              let screen = NSScreen.screens.first(where: { $0.auxiliaryTopRightArea != nil }),
              abs(screen.frame.width - values[2]) < 1, abs((screen.auxiliaryTopRightArea?.minX ?? 0) - values[1]) < 1 else { return nil }
        return (CGFloat(values[0]), CGFloat(values[1]))
    }
    private var rebuilding = false
    /// When the items were last created: macOS needs a moment to place them, and until then their frames are wrong.
    private var itemsCreatedAt = -Double.infinity

    private var currentStep: MenubarFit.Step {
        ladder.isEmpty ? MenubarFit.Step(moduleCount: configuredModules.count, labels: configuredLabels)
            : ladder[min(fitLevel, ladder.count - 1)].step
    }

    /// Measures every step of the ladder from the modules' current widths (no drawing).
    private func updateLadder(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - ladderTime > 4 else { return }
        ladderTime = now
        let modules = configuredModules
        let combined = settings.layout == .combined
        ladder = MenubarFit.ladder(count: modules.count, labelsConfigured: configuredLabels) { step in
            var options = MenubarOptions(settings)
            options.showLabels = step.labels
            let context = makeContext(options: options)
            let widths = modules.prefix(step.moduleCount).map { MenubarRenderer.segment(for: $0, context: context).width }
            // Each item is its image plus 2 points (see render) plus the padding macOS draws around it; separate
            // items also have macOS' gap between them.
            let padding = itemPadding
            if combined {
                return ceil(widths.reduce(0, +) + MenubarRenderer.segmentGap * CGFloat(max(widths.count - 1, 0))) + 2 + padding
            }
            return widths.map { ceil($0) + 2 + padding }.reduce(0, +) + Self.itemGap * CGFloat(max(widths.count - 1, 0))
        }
        fitLevel = min(fitLevel, max(ladder.count - 1, 0))
        let summary = ladder.map { "\($0.step.moduleCount)\($0.step.labels ? "E" : "")=\(Int($0.width))" }.joined(separator: " ")
        if summary != lastLadderSummary {
            lastLadderSummary = summary
            debug("scala dei passi: \(summary)")
        }
    }

    private var lastLadderSummary = ""

    /// Space macOS leaves between two status items.
    private static let itemGap: CGFloat = 8

    /// What macOS adds around an item's length (its window is wider than `length`), measured on a visible item.
    private var itemPadding: CGFloat {
        guard let entry = entries.first, let window = entry.item.button?.window, window.isVisible, entry.item.length > 0
        else { return 16 }
        return min(max(window.frame.width - entry.item.length, 0), 40)
    }

    /// The room MenuStats may use, measured on displays with a notch; nil where it can't be measured.
    private func measuredRoom() -> CGFloat? {
        if roomUnreliable { return nil }
        let visible = entries.compactMap { entry -> NSWindow? in
            guard let window = entry.item.button?.window, window.isVisible, !isOutOfRoom(window) else { return nil }
            return window
        }
        let placed = ProcessInfo.processInfo.systemUptime - itemsCreatedAt > 1.5
        if placed, visible.count == entries.count, let right = visible.map(\.frame.maxX).max(), let screen = visible.first?.screen {
            let notch = screen.auxiliaryTopRightArea?.minX
            // Items always sit right of the notch: anything else is a frame macOS hasn't settled yet.
            if notch.map({ right > $0 }) ?? true { lastGeometry = (right, notch) }
        }
        guard let geometry = lastGeometry else { return nil }
        return MenubarFit.room(rightEdge: geometry.rightEdge, notchRightEdge: geometry.notchRightEdge)
    }

    /// Shows the widest step that fits the measured room, if it can be measured.
    private func applyRoom() {
        guard settings.autoFitMenubar, !rebuilding, let room = measuredRoom() else { return }
        let target = MenubarFit.choose(ladder, room: room, current: fitLevel)
        guard target != fitLevel else { return }
        debug("spazio \(Int(room)) pt: passo \(fitLevel) -> \(target) (\(ladder[target].step), \(Int(ladder[target].width)) pt)")
        fitLevel = target
        rebuild()
    }

    /// Diagnostics for the automatic fit, on with `MENUSTATS_DEBUG=1` (run the app from a terminal to read them).
    private func debug(_ text: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["MENUSTATS_DEBUG"] != nil else { return }
        NSLog("MENUSTATS \(text())")
    }
    private var pinApplied: Bool?
    private var fitCheck: DispatchWorkItem?
    private var confirmation = FitConfirmation()

    private var maxFitLevel: Int { max(ladder.count - 1, 0) }

    /// Where macOS put the items, as one number that changes when any of them moves or resizes.
    private var layoutSignature: Double {
        entries.reduce(0) { total, entry in
            guard let frame = entry.item.button?.window?.frame else { return total }
            return total + Double(frame.minX) * 3 + Double(frame.width)
        }
    }

    private var restoreWork: DispatchWorkItem?

    private func scheduleRestore() {
        guard restoreWork == nil, let delay = confirmation.restoreDelay else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            restoreWork = nil
            guard fitLevel > 0 else { return }
            debug("prova a ripristinare: livello \(fitLevel) -> \(fitLevel - 1)")
            fitLevel -= 1
            confirmation.beganRestore(at: Date())
            confirmation.layoutChanged(at: Date(), signature: layoutSignature)
            rebuild()
        }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// macOS places items with a smaller preferred position closer to the clock. Written before each item is
    /// created, so MenuStats stays at the right end and other apps' icons overflow first.
    private func pin(_ autosaveName: String, rank: Int) {
        guard settings.pinNearClock else { return }
        UserDefaults.standard.set(Double(rank + 1), forKey: "NSStatusItem Preferred Position \(autosaveName)")
    }

    /// True when macOS isn't showing the item: behind the notch, pushed off screen or into the overflow.
    /// Whether macOS left the item out for lack of room: ordered out, off screen or behind the notch. The window's
    /// occlusion state is not used: it also turns "not visible" whenever the front app keeps a window over the menu bar
    /// (Claude keeps a transparent one there), when MenuStats itself is in front, or on the lock screen, and shrinking on
    /// it collapsed the bar to the CPU alone.
    private func isOutOfRoom(_ item: NSStatusItem) -> Bool {
        guard let window = item.button?.window else { return false }
        return !window.isVisible || isOutOfRoom(window)
    }

    /// Ordered out, off screen or behind the notch: macOS had no room for it.
    private func isOutOfRoom(_ window: NSWindow) -> Bool {
        let frame = window.frame
        if Self.isOverHiddenMenuBar(frame) { return false }
        if Self.isHiddenInPlace(frame) { return true }
        guard let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(frame) }) else { return true }
        if frame.maxX <= screen.frame.minX || frame.minX >= screen.frame.maxX { return true }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           frame.maxX > left.maxX + 1, frame.minX < right.minX - 1 { return true }
        return false
    }

    /// On macOS 26 an item that no longer fits (say, once the microphone indicator appears) can be hidden where it
    /// stands, its frame unchanged; only the window server's on-screen flag tells. The menu bar windows belong to
    /// Control Center there, so the item is looked up by its bounds. False when no such window is listed (older
    /// systems rely on the frame) and when no other icon of the same menu bar is on screen (display asleep, bar hidden).
    private static func isOverHiddenMenuBar(_ frame: NSRect) -> Bool {
        MenubarFit.isOverHiddenMenuBar(frame, screens: NSScreen.screens.map(\.frame))
    }

    private static func isHiddenInPlace(_ frame: NSRect) -> Bool {
        guard let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let top = primary.frame.maxY - frame.maxY // window server coordinates start at the top left
        let level = Int(CGWindowLevelForKey(.statusWindow))
        // Only the icons in the same menu bar count: each display has its own, and one may be hidden.
        let display = NSScreen.screens.first { $0.frame.minX <= frame.midX && frame.midX <= $0.frame.maxX }?.frame
        var found = false, shown = false, othersShown = false
        for info in list where info[kCGWindowLayer as String] as? Int == level {
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            let onScreen = info[kCGWindowIsOnscreen as String] as? Bool == true
            if abs(bounds.minX - frame.minX) < 1, abs(bounds.width - frame.width) < 1, abs(bounds.minY - top) < 1 {
                found = true
                shown = shown || onScreen
            } else if onScreen, abs(bounds.minY - top) < 1, display.map({ $0.minX <= bounds.midX && bounds.midX <= $0.maxX }) ?? true {
                othersShown = true
            }
        }
        return found && !shown && othersShown
    }

    /// Set when macOS hid an item where it stands: the room measured from the notch is then too generous (something
    /// the frames don't show takes space), so the bar widens one try at a time instead.
    private var roomUnreliable = false

    private func scheduleFitCheck(after delay: Double = 0.6) {
        fitCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.fitCheck = nil
            self?.checkFit()
        }
        fitCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func checkFit() {
        guard settings.autoFitMenubar, !entries.isEmpty else { return }
        let hidden = entries.contains { isOutOfRoom($0.item) }
        let verdict = confirmation.observe(hidden: hidden, signature: layoutSignature, at: Date())
        if ProcessInfo.processInfo.environment["MENUSTATS_DEBUG"] != nil {
            let details = entries.map { entry -> String in
                guard let window = entry.item.button?.window else { return "senza finestra" }
                return "visibile=\(window.isVisible) occlusione=\(window.occlusionState.rawValue) schermo=\(window.screen?.frame ?? .zero) frame=\(window.frame)"
            }
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            let screen = entries.first?.item.button?.window?.screen
            let bar = screen.map { "barra=\($0.frame.maxY - $0.visibleFrame.maxY) schermo=\($0.frame) visibile=\($0.visibleFrame)" } ?? "senza schermo"
            NSLog("MENUSTATS spazio: app in primo piano=\(front) \(bar) livello \(fitLevel), fuori spazio \(hidden), verdetto \(verdict), \(details)")
        }
        switch verdict {
        case .fine:
            // Back to the full bar: the room can be measured again.
            if fitLevel == 0, !confirmation.confirmingRestore { roomUnreliable = false }
            // Where the room is measured it decides; elsewhere try one step wider after a while.
            if !roomUnreliable, lastGeometry?.notchRightEdge != nil { applyRoom() } else if fitLevel > 0 { scheduleRestore() }
        case .wait(let seconds): scheduleFitCheck(after: seconds)
        case .shrink:
            guard fitLevel < maxFitLevel else { return }
            if !roomUnreliable, entries.contains(where: { $0.item.button?.window.map { Self.isHiddenInPlace($0.frame) } == true }) {
                debug("nascosto da macOS senza spostarlo: lo spazio misurato dal notch non vale")
                roomUnreliable = true
            }
            debug("nascosto da macOS: passo \(fitLevel) -> \(fitLevel + 1)")
            fitLevel += 1
            // The measured room was wrong (an icon appeared to the right): measure again once visible.
            lastGeometry = nil
            confirmation.layoutChanged(at: Date(), signature: layoutSignature)
            rebuild()
        }
    }

    /// Something that may change the room in the menu bar happened (an app launched or quit, another display).
    /// With a measured room MenuStats picks the right step at once; elsewhere it tries one step wider at a time.
    private func resetFit() {
        debug("lo spazio potrebbe essere cambiato (passo \(fitLevel))")
        // While an indicator hides MenuStats in place, apps coming and going say nothing about the room: keep the
        // growing wait between tries, or the bar would flicker at every launch.
        if !roomUnreliable { confirmation.roomMayHaveChanged() }
        if !roomUnreliable, lastGeometry?.notchRightEdge != nil {
            applyRoom()
            scheduleFitCheck()
        } else if fitLevel > 0 {
            scheduleRestore()
        } else {
            scheduleFitCheck()
        }
    }

    private func observeRoom() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Apps add or remove their icons a moment after launching or quitting.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.resetFit() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            self?.lastGeometry = nil // the notch and the edges may be elsewhere now
            self?.roomUnreliable = false
            self?.resetFit()
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil,
                                               queue: .main) { [weak self] note in
            guard let self, let window = note.object as? NSWindow,
                  entries.contains(where: { $0.item.button?.window === window }) else { return }
            debug("occlusione cambiata: visibile=\(window.occlusionState.contains(.visible)) frame=\(window.frame)")
            scheduleFitCheck(after: 0.3)
        }
    }

    private func rebuild() {
        rebuilding = true
        defer { rebuilding = false }
        updateLadder(force: true)
        if settings.autoFitMenubar, let room = measuredRoom() {
            fitLevel = MenubarFit.choose(ladder, room: room, current: fitLevel)
        }
        let wanted = structure
        // Turning "next to the clock" on recreates the items, since macOS reads the position only when one is created.
        if wanted != entries.map(\.modules) || (settings.pinNearClock && pinApplied != true) {
            pinApplied = settings.pinNearClock
            confirmation.layoutChanged(at: Date(), signature: layoutSignature)
            entries.forEach { NSStatusBar.system.removeStatusItem($0.item) }
            itemsCreatedAt = ProcessInfo.processInfo.systemUptime
            // New status items appear to the left of older ones, so create them right-to-left.
            entries = wanted.reversed().enumerated().map { rank, modules in
                let name = "MenuStats." + (wanted.count == 1 ? "combined" : modules[0].rawValue)
                pin(name, rank: rank)
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = name
                item.button?.target = self
                item.button?.action = #selector(clicked(_:))
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                item.button?.imagePosition = .imageOnly
                return Entry(item: item, modules: modules)
            }.reversed()
        }
        render()
        updateAnimation()
        updateClock()
        scheduleFitCheck()
    }

    private func makeContext(options: MenubarOptions) -> MenubarRenderer.Context {
        MenubarRenderer.Context(
            snapshot: model.snapshot,
            options: options,
            recent: { [weak model] metric, count in model?.recentValues(metric, count: count) ?? [] },
            fanAngle: fanAngle,
            steamPhase: steamPhase,
            weather: model.weather.report,
            weatherConfigured: settings.weatherLocation != nil,
            awake: model.awake.state
        )
    }

    private func render() {
        var options = MenubarOptions(settings)
        if !configuredLabels || (settings.autoFitMenubar && !currentStep.labels) { options.showLabels = false }
        let context = makeContext(options: options)
        defer {
            if settings.autoFitMenubar && !rebuilding {
                updateLadder()
                applyRoom()
                // Nothing announces a microphone or camera indicator taking room: look at every sample.
                if fitCheck == nil, fitLevel < maxFitLevel, entries.contains(where: { isOutOfRoom($0.item) }) { scheduleFitCheck() }
            }
        }
        for index in entries.indices {
            guard let button = entries[index].item.button else { continue }
            let rendered = MenubarRenderer.image(for: entries[index].modules, context: context)
            // Rasterize once, in the menu bar's appearance, and hand AppKit a bitmap only when its pixels changed:
            // an NSImage drawing handler would re-run text layout on every redraw of the menu bar.
            let appearance = button.effectiveAppearance
            let bitmap = Self.rasterize(rendered.image, appearance: appearance,
                                        scale: button.window?.backingScaleFactor ?? 2)
            if bitmap.pixels != entries[index].pixels || entries[index].appearanceName != appearance.name {
                entries[index].appearanceName = appearance.name
                button.image = bitmap.image
                entries[index].pixels = bitmap.pixels
            }
            // Exact width instead of variableLength (which pads both sides). Only when it changes:
            // every length change makes macOS re-layout the whole menu bar.
            let length = ceil(rendered.image.size.width) + 2
            if abs(entries[index].item.length - length) > 0.5 {
                entries[index].item.length = length
                confirmation.layoutChanged(at: Date(), signature: layoutSignature)
                scheduleFitCheck() // a wider value can push MenuStats out of the bar
            }
            entries[index].hitRanges = rendered.hitRanges
            entries[index].imageWidth = rendered.image.size.width
        }
    }

    private static func rasterize(_ image: NSImage, appearance: NSAppearance, scale: CGFloat) -> (image: NSImage, pixels: Data) {
        let size = image.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width * scale)),
                                         pixelsHigh: Int(ceil(size.height * scale)), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return (image, Data()) }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance { image.draw(in: NSRect(origin: .zero, size: size)) }
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: size)
        result.addRepresentation(rep)
        result.isTemplate = image.isTemplate
        let pixels = rep.bitmapData.map { Data(bytes: $0, count: rep.bytesPerRow * rep.pixelsHigh) } ?? Data()
        return (result, pixels)
    }

    // MARK: - Fan and steam animation

    private var shouldAnimateFan: Bool {
        settings.dynamicIcons && settings.isEnabled(.fans) && model.snapshot.fansSpinning
    }

    /// Steam rises from the cup while an Awake session runs.
    private var shouldAnimateSteam: Bool {
        settings.dynamicIcons && settings.isEnabled(.awake) && model.awake.state.isActive
    }

    private func updateAnimation() {
        let animate = shouldAnimateFan || shouldAnimateSteam
        if animate, animationTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in self?.advanceAnimation() }
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        } else if !animate, animationTimer != nil {
            animationTimer?.invalidate()
            animationTimer = nil
            fanAngle = 0
            steamPhase = 0
            render()
        }
    }

    private func advanceAnimation() {
        if shouldAnimateFan {
            let fraction = model.snapshot.smc?.fans.map(\.fraction).max() ?? 0
            // 0.4–2 revolutions per second depending on fan speed.
            fanAngle -= CGFloat(2 * Double.pi * (0.4 + 1.6 * fraction) / 12)
        } else {
            fanAngle = 0
        }
        // One steam cycle every 2.5 s.
        steamPhase = shouldAnimateSteam ? (steamPhase + 1 / (12 * 2.5)).truncatingRemainder(dividingBy: 1) : 0
        render()
    }

    // MARK: - Clicks

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let entry = entries.first(where: { $0.item.button === sender }), let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showQuickMenu(for: entry.item)
            return
        }

        // The image is centered in the button; map the click to a segment.
        let location = sender.convert(event.locationInWindow, from: nil)
        let offset = (sender.bounds.width - entry.imageWidth) / 2
        let x = location.x - offset
        let range = entry.hitRanges.first { $0.1.contains(x) } ?? entry.hitRanges.min {
            abs(($0.1.lowerBound + $0.1.upperBound) / 2 - x) < abs(($1.1.lowerBound + $1.1.upperBound) / 2 - x)
        }
        guard let (module, segment) = range, let window = sender.window else { return }

        let midX = offset + (segment.lowerBound + segment.upperBound) / 2
        let pointInWindow = sender.convert(NSPoint(x: midX, y: sender.bounds.minY), to: nil)
        let anchor = window.convertPoint(toScreen: pointInWindow)
        panel.toggle(tab: module.tab, anchor: NSPoint(x: anchor.x, y: window.frame.minY))
    }

    /// Screen anchor under a module's segment (bottom-center), as a click there would compute.
    func anchor(for module: ModuleID) -> NSPoint? {
        guard let entry = entries.first(where: { $0.modules.contains(module) }), let button = entry.item.button,
              let window = button.window, let range = entry.hitRanges.first(where: { $0.0 == module })?.1 else { return nil }
        let offset = (button.bounds.width - entry.imageWidth) / 2
        let point = window.convertPoint(toScreen: button.convert(NSPoint(x: offset + (range.lowerBound + range.upperBound) / 2, y: 0), to: nil))
        return NSPoint(x: point.x, y: window.frame.minY)
    }

    /// The status item buttons, for self-test captures.
    var buttons: [NSStatusBarButton] { entries.compactMap { $0.item.button } }

    private func showQuickMenu(for item: NSStatusItem) {
        panel.close()
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Impostazioni…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let activity = NSMenuItem(title: "Apri Monitoraggio Attività", action: #selector(openActivityMonitor), keyEquivalent: "")
        activity.target = self
        menu.addItem(activity)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Esci da MenuStats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil // restore left-click handling
    }

    @objc private func openSettingsAction() { openSettings() }
    @objc private func openActivityMonitor() { SystemActions.openActivityMonitor() }
}
