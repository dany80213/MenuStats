import AppKit
import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// What the menu bar and the dashboard need to draw the Awake module.
struct AwakeState: Equatable {
    /// How the running session ends.
    enum Kind: Equatable {
        /// At `endDate`, or never when there is none.
        case timed
        /// When the file stops growing for a while or disappears; `progress` comes from the macOS download badge if any.
        case download(name: String, progress: Double?)
        /// When the app quits.
        case app(name: String)
        /// While AI tools report they are working (`working` = how many), then it ends by itself.
        case ai(working: Int)
    }

    var isActive = false
    var kind = Kind.timed
    /// nil: until stopped (or, for downloads and apps, until their own end).
    var endDate: Date?
    var startDate: Date?
    var allowsDisplaySleep = false
    var isAI: Bool { if case .ai = kind { return isActive } else { return false } }
    /// For AI sessions: the tools at work, one entry per session ("Claude Code", "Codex").
    var aiTools: [String] = []

    /// An active session with 1 h 30 min left, for the style previews in Settings.
    static var sample: AwakeState {
        AwakeState(isActive: true, endDate: Date().addingTimeInterval(5400), startDate: Date(), allowsDisplaySleep: false)
    }

    func remaining(at now: Date = Date()) -> TimeInterval? {
        endDate.map { max($0.timeIntervalSince(now), 0) }
    }
}

/// Keeps the Mac awake with the same public power assertions that `caffeinate` uses: one stops idle system sleep,
/// an optional second one keeps the display on. Both are released when the session ends or MenuStats quits.
/// A session can last a set time, until a file stops downloading, or while an app is running.
/// Closing the lid still puts the Mac to sleep, unless the user turned on "lid closed" and installed the root helper:
/// then the helper holds it for the session, with its own failsafes (see LidController in MenuStatsHelper).
final class AwakeController: ObservableObject {
    @Published private(set) var state = AwakeState()
    /// Why the last session ended on its own (timer, low battery, download done…); cleared when a new one starts.
    @Published private(set) var lastEndReason: String?

    static let durations: [(label: String, minutes: Int?)] = [
        ("15 min", 15), ("30 min", 30), ("1 h", 60), ("2 h", 120), ("4 h", 240), ("8 h", 480), ("Sempre", nil),
    ]

    /// How long a download may stay at the same size before it counts as finished.
    static let downloadTimeouts: [(label: String, seconds: Int)] = [
        ("10 secondi", 10), ("30 secondi", 30), ("1 minuto", 60), ("5 minuti", 300), ("10 minuti", 600), ("30 minuti", 1800),
    ]

    private let settings: Settings
    /// The root helper's client, for lid-closed awake; nil in tests.
    private let hardware: HardwareControl?
    /// Renews the helper's lid lease. Separate from sampling, which pauses while the displays sleep (lid closed).
    private var lidTimer: Timer?
    /// Keeps App Nap from stretching `lidTimer` while the displays are off, which would let the lease run out.
    private var lidActivity: NSObjectProtocol?
    /// While the lid is held awake ("SleepDisabled") macOS may not turn the display off by itself: when the session
    /// lets the display sleep, this timer does it after the display-sleep delay set in macOS.
    private var displayTimer: Timer?
    private var systemAssertion = IOPMAssertionID(kIOPMNullAssertionID)
    private var displayAssertion = IOPMAssertionID(kIOPMNullAssertionID)
    private var timer: Timer?
    private var terminationObserver: NSObjectProtocol?

    // File watching
    private var watchedFile: URL?
    private var lastSize: UInt64 = 0
    private var secondsWithoutGrowth = 0

    // AI activity: recognized automatically (AIActivityMonitor); tools may also drop a file in `aiDirectory`
    // when they start working and delete it when done.
    static let aiDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".menustats/ai")
    private var aiTimer: Timer?
    private lazy var aiMonitor = AIActivityMonitor()
    /// Seconds after Claude's Stop event before the session ends.
    static let hookGrace: TimeInterval = 10
    private var claudeHooked = false
    private var hooksCheckedAt = Date.distantPast
    private var lastWorkFromHooks = false
    /// Replaces the real detection in tests.
    var aiReading: (() -> AIActivityMonitor.Reading)?
    /// When the last AI activity stopped; the session ends once this is older than the chosen grace period.
    private var aiIdleSince: Date?
    /// After the user ends an AI session by hand, the same activity does not restart it; it re-arms once the AI is idle.
    private var aiSnoozed = false

    init(settings: Settings, hardware: HardwareControl? = nil) {
        self.settings = settings
        self.hardware = hardware
        if settings.awakeWatchAI { startWatchingAI() }
    }

    deinit { releaseAssertions() }

    // MARK: - Starting

    /// Starts a session (or restarts it with a new duration). `minutes` nil: until stopped.
    func start(minutes: Int?) {
        let end = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        guard begin(kind: .timed, end: end) else { return }
        if let end {
            let timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in self?.stop(reason: "Tempo scaduto") }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    /// Stays awake while `file` (a download in progress) keeps growing; ends once its size has not changed for
    /// `timeout` seconds, or when it is gone. Folders (like Safari's .download packages) count all their contents.
    func start(watching file: URL, timeout: Int) {
        guard begin(kind: .download(name: file.lastPathComponent, progress: nil), end: nil) else { return }
        watchedFile = file
        lastSize = Self.size(of: file) ?? 0
        secondsWithoutGrowth = 0
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkFile(timeout: timeout) }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stays awake while `app` is running.
    func start(whileRunning app: NSRunningApplication) {
        let name = app.localizedName ?? app.bundleIdentifier ?? "App"
        guard begin(kind: .app(name: name), end: nil) else { return }
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let quit = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  quit.processIdentifier == app.processIdentifier else { return }
            self?.stop(reason: "\(name) è stata chiusa")
        }
        if app.isTerminated { stop(reason: "\(name) è stata chiusa") }
    }

    func stop() { stop(reason: nil) }

    /// Adds or removes the display assertion in the running session; the system assertion stays.
    func setAllowDisplaySleep(_ allow: Bool) {
        if case .ai = state.kind, state.isActive {
            settings.awakeAIAllowDisplaySleep = allow
        } else {
            settings.awakeAllowDisplaySleep = allow
        }
        guard state.isActive else { return }
        if allow {
            releaseAssertion(&displayAssertion)
        } else if displayAssertion == IOPMAssertionID(kIOPMNullAssertionID) {
            _ = createAssertion(kIOPMAssertPreventUserIdleDisplaySleep, "MenuStats: schermo acceso", &displayAssertion)
        }
        state.allowsDisplaySleep = allow
    }

    /// Turns lid-closed awake on or off, for the running session too.
    func setLidClosed(_ on: Bool) {
        settings.awakeLidClosed = on
        guard state.isActive else { return }
        if on { holdLid() } else { releaseLid() }
    }

    /// Turns "stay awake while an AI works" on or off (kept across launches).
    func setWatchAI(_ on: Bool) {
        settings.awakeWatchAI = on
        if on {
            startWatchingAI()
        } else {
            aiTimer?.invalidate()
            aiTimer = nil
            if case .ai = state.kind, state.isActive { stop(reason: nil) }
            aiSnoozed = false
        }
    }

    /// Called on every sample: ends the session when the battery runs low.
    func evaluate(_ snapshot: Snapshot) {
        guard state.isActive, settings.awakeEndOnLowBattery, let battery = snapshot.battery,
              !battery.onACPower, battery.percent <= settings.awakeLowBatteryThreshold else { return }
        stop(reason: "Batteria sotto il \(Format.percent(settings.awakeLowBatteryThreshold))")
    }

    // MARK: - Session lifecycle

    private func begin(kind: AwakeState.Kind, end: Date?) -> Bool {
        stop(reason: nil)
        var allowsDisplaySleep = settings.awakeAllowDisplaySleep
        if case .ai = kind { allowsDisplaySleep = settings.awakeAIAllowDisplaySleep }
        guard createAssertion(kIOPMAssertPreventUserIdleSystemSleep, "MenuStats: Mac sveglio", &systemAssertion) else { return false }
        if !allowsDisplaySleep {
            _ = createAssertion(kIOPMAssertPreventUserIdleDisplaySleep, "MenuStats: schermo acceso", &displayAssertion)
        }
        state = AwakeState(isActive: true, kind: kind, endDate: end, startDate: Date(), allowsDisplaySleep: allowsDisplaySleep)
        lastEndReason = nil
        if settings.awakeLidClosed { holdLid() }
        return true
    }

    private func stop(reason: String?) {
        if state.isActive, case .ai = state.kind { aiSnoozed = true }
        timer?.invalidate()
        timer = nil
        if let terminationObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver) }
        terminationObserver = nil
        watchedFile = nil
        releaseLid()
        releaseAssertions()
        if state.isActive { state = AwakeState(isActive: false, allowsDisplaySleep: settings.awakeAllowDisplaySleep) }
        if let reason { lastEndReason = reason }
    }

    // MARK: - Lid closed

    private func holdLid() {
        guard let hardware else { return }
        hardware.setLidAwake(true)
        startDisplayGuard()
        guard lidTimer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak hardware] _ in hardware?.renewLidAwake() }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        lidTimer = timer
        lidActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                            reason: "Rinnovo del Mac sveglio a coperchio chiuso")
    }

    private func releaseLid() {
        displayTimer?.invalidate()
        displayTimer = nil
        lidTimer?.invalidate()
        lidTimer = nil
        if let lidActivity { ProcessInfo.processInfo.endActivity(lidActivity) }
        lidActivity = nil
        hardware?.setLidAwake(false)
    }

    // MARK: - Display while the lid is held

    /// The lid is closed: the built-in screen is turned off at once (nobody can see it and it drains the battery),
    /// whatever "Lascia spegnere lo schermo" says; the Mac keeps working. With the lid open, when the session lets the
    /// display sleep, it goes off after the idle delay set in macOS, which "SleepDisabled" would otherwise ignore.
    private func startDisplayGuard() {
        guard displayTimer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.guardDisplay() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
        guardDisplay()
    }

    private var lidWasClosed = false
    private var displaySleepCache: (minutes: Int?, time: Date) = (nil, .distantPast)

    private func guardDisplay() {
        guard state.isActive else { return }
        if Self.lidIsClosed() {
            if !lidWasClosed {
                lidWasClosed = true
                // The "screen on" assertion would wake the display again: not needed with the lid closed.
                releaseAssertion(&displayAssertion)
            }
            // In clamshell mode with an external display the user works on that one: leave it alone.
            if !Self.hasAwakeExternalDisplay(), Self.builtInDisplayIsAwake() { Self.sleepDisplayNow() }
            return
        }
        if lidWasClosed {
            lidWasClosed = false
            if !state.allowsDisplaySleep, displayAssertion == IOPMAssertionID(kIOPMNullAssertionID) {
                _ = createAssertion(kIOPMAssertPreventUserIdleDisplaySleep, "MenuStats: schermo acceso", &displayAssertion)
            }
        }
        sleepDisplayIfIdle()
    }

    private func sleepDisplayIfIdle() {
        guard state.allowsDisplaySleep, CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return }
        // `pmset -g` is a process launch: read the delay once a minute.
        if Date().timeIntervalSince(displaySleepCache.time) > 60 { displaySleepCache = (Self.displaySleepMinutes(), Date()) }
        guard let minutes = displaySleepCache.minutes, minutes > 0 else { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        guard idle >= Double(minutes) * 60 else { return }
        Self.sleepDisplayNow()
    }

    static func sleepDisplayNow() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }

    /// "AppleClamshellState" of the power manager: true while the lid is closed. Readable without privileges.
    static func lidIsClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }

    private static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    static func hasAwakeExternalDisplay() -> Bool {
        onlineDisplays().contains { CGDisplayIsBuiltin($0) == 0 && CGDisplayIsAsleep($0) == 0 }
    }

    static func builtInDisplayIsAwake() -> Bool {
        onlineDisplays().contains { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsAsleep($0) == 0 }
    }

    /// "displaysleep" from the active power settings (`pmset -g`), in minutes; 0 means never.
    static func displaySleepMinutes() -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return parseDisplaySleep(output)
    }

    static func parseDisplaySleep(_ pmsetOutput: String) -> Int? {
        for line in pmsetOutput.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if fields.count >= 2, fields[0] == "displaysleep" { return Int(fields[1]) }
        }
        return nil
    }

    // MARK: - AI activity

    private func startWatchingAI() {
        guard aiTimer == nil else { return }
        try? FileManager.default.createDirectory(at: Self.aiDirectory, withIntermediateDirectories: true)
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.checkAI() }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        aiTimer = timer
        checkAI()
    }

    /// How many AI tools report working: files in the folder that were refreshed recently.
    static func aiWorkingCount(staleAfter minutes: Int, now: Date = Date(), in directory: URL = aiDirectory) -> Int {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys,
                                                                   options: [.skipsHiddenFiles])) ?? []
        return files.filter { file in
            guard let modified = try? file.resourceValues(forKeys: Set(keys)).contentModificationDate else { return false }
            return now.timeIntervalSince(modified) < Double(minutes) * 60
        }.count
    }

    /// "Claude Code al lavoro", "2 sessioni di Claude Code e Codex al lavoro".
    static func describe(_ tools: [String]) -> String {
        guard !tools.isEmpty else { return "IA al lavoro" }
        var names: [String] = []
        for tool in tools where !names.contains(tool) { names.append(tool) }
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " e " + names.last! : names[0]
        return tools.count > names.count ? "\(tools.count) sessioni di \(list) al lavoro" : "\(list) al lavoro"
    }

    /// Shell commands any tool can run: mark "working" (also refreshes it) and "done". `name` identifies the tool/session.
    static func aiStartCommand(name: String) -> String { "mkdir -p ~/.menustats/ai && touch ~/.menustats/ai/\(name)" }
    static func aiStopCommand(name: String) -> String { "rm -f ~/.menustats/ai/\(name)" }

    /// Claude Code events that mean "working" (also refresh the signal) and "done" (remove it). Notification fires
    /// when Claude waits for the user (a permission, an answer): not working, so the Mac may sleep meanwhile.
    static let claudeWorkingEvents = ["UserPromptSubmit", "PreToolUse", "PostToolUse"]
    static let claudeDoneEvents = ["Stop", "SessionEnd", "Notification"]
    /// Marks our commands, to recognize them in settings.json.
    static let hookMarker = ".menustats/ai"

    /// The commands of the hooks. Claude Code sends the session id as JSON on stdin, so each session gets its own file
    /// and several can work at once.
    static func claudeHookCommands() -> (working: String, done: String) {
        // `tr` keeps only letters, digits, "-" and "_": the id can never add a "/" and leave the folder.
        let session = #"s=$(sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p' | head -1 | tr -cd 'A-Za-z0-9_-'); f="$HOME/.menustats/ai/claude-${s:-x}"; "#
        return (session + #"mkdir -p "$HOME/.menustats/ai" && touch "$f""#, session + #"rm -f "$f""#)
    }

    private static func hookEntries() -> [String: [[String: Any]]] {
        let commands = claudeHookCommands()
        func event(_ command: String) -> [[String: Any]] { [["hooks": [["type": "command", "command": command]]]] }
        var hooks: [String: [[String: Any]]] = [:]
        for name in claudeWorkingEvents { hooks[name] = event(commands.working) }
        for name in claudeDoneEvents { hooks[name] = event(commands.done) }
        return hooks
    }

    /// The `hooks` section for Claude Code's settings.json (shown and copied in Settings).
    static func claudeCodeHooksJSON() -> String {
        let data = try? JSONSerialization.data(withJSONObject: ["hooks": hookEntries()], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static let claudeSettingsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")

    /// True when Claude Code's settings contain MenuStats' hooks for every event.
    static func claudeHooksInstalled(settings url: URL = claudeSettingsURL) -> Bool {
        guard let data = try? Data(contentsOf: url), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return (claudeWorkingEvents + claudeDoneEvents).allSatisfy { name in
            ((hooks[name] as? [[String: Any]]) ?? []).contains(where: isOurs)
        }
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        ((group["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.contains(hookMarker) == true }
    }

    /// Adds (or with `install: false` removes) MenuStats' hooks in Claude Code's settings.json, keeping everything else.
    /// The file as it was is saved next to it once, as settings.json.menustats-backup.
    static func setClaudeHooks(installed install: Bool, settings url: URL = claudeSettingsURL) throws {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "MenuStats", code: 1, userInfo: [NSLocalizedDescriptionKey: "settings.json di Claude non è un oggetto JSON"])
            }
            root = parsed
            let backup = url.appendingPathExtension("menustats-backup")
            if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup) }
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for name in claudeWorkingEvents + claudeDoneEvents {
            var groups = ((hooks[name] as? [[String: Any]]) ?? []).filter { !isOurs($0) }
            if install { groups += hookEntries()[name] ?? [] }
            hooks[name] = groups.isEmpty ? nil : groups
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    func checkAI(now: Date = Date()) {
        if now.timeIntervalSince(hooksCheckedAt) > 30 {
            hooksCheckedAt = now
            claudeHooked = Self.claudeHooksInstalled()
        }
        let reading = aiReading?() ?? aiMonitor.sample(hookStaleMinutes: settings.awakeAIStaleMinutes,
                                                       hookedTools: claudeHooked ? ["Claude Code"] : [], now: now)
        if reading.isWorking { lastWorkFromHooks = reading.onlyHooks }
        if reading.isWorking { aiIdleSince = nil } else if aiIdleSince == nil { aiIdleSince = now }
        // Hooks say exactly when the work ends: a few seconds are enough (a new prompt right after keeps the session).
        // Estimates can't tell a thinking pause from the end: only a long quiet spell counts.
        let grace = lastWorkFromHooks ? Self.hookGrace : Double(settings.awakeAIGraceMinutes) * 60
        let finished = aiIdleSince.map { now.timeIntervalSince($0) >= grace } ?? false
        if finished { aiSnoozed = false }
        if case .ai = state.kind, state.isActive {
            if finished {
                stop(reason: "L'IA ha finito di lavorare")
                aiSnoozed = false // only a manual stop holds back the next AI session
            } else if reading.isWorking, state.aiTools != reading.sessions {
                state.kind = .ai(working: reading.sessions.count)
                state.aiTools = reading.sessions
            }
        } else if reading.isWorking, !state.isActive, !aiSnoozed {
            guard begin(kind: .ai(working: reading.sessions.count), end: nil) else { return }
            state.aiTools = reading.sessions
        }
    }

    // MARK: - File watching

    private func checkFile(timeout: Int) {
        guard let file = watchedFile, state.isActive else { return }
        guard let size = Self.size(of: file) else { stop(reason: "File non più presente"); return }

        if size > lastSize {
            lastSize = size
            secondsWithoutGrowth = 0
        } else {
            secondsWithoutGrowth += 1
        }
        let progress = Self.downloadProgress(of: file)
        if case .download(let name, let shown) = state.kind, shown != progress {
            state.kind = .download(name: name, progress: progress)
        }
        if secondsWithoutGrowth >= timeout || (progress ?? 0) >= 1 {
            stop(reason: "Download terminato: \(file.lastPathComponent)")
        }
    }

    /// Size in bytes of a file, or of the files directly inside a folder (Safari's ".download" package keeps its data there);
    /// nil when it does not exist. Folders are not walked deeply and are capped, since this runs every second.
    private static func size(of url: URL) -> UInt64? {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        guard isDirectory.boolValue else {
            return (try? manager.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        }
        let keys: [URLResourceKey] = [.fileSizeKey]
        let items = (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)) ?? []
        return items.prefix(500).reduce(UInt64(0)) { total, item in
            total + UInt64((try? item.resourceValues(forKeys: Set(keys)).fileSize) ?? 0)
        }
    }

    /// The fraction (0…1) macOS stores on files being downloaded by Safari, Finder and others, if present.
    private static func downloadProgress(of url: URL) -> Double? {
        let name = "com.apple.progress.fractionCompleted"
        let length = getxattr(url.path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard getxattr(url.path, name, &buffer, length, 0, 0) == length,
              let text = String(bytes: buffer, encoding: .utf8), let value = Double(text) else { return nil }
        return min(max(value, 0), 1)
    }

    // MARK: - Assertions

    private func createAssertion(_ type: String, _ name: String, _ id: inout IOPMAssertionID) -> Bool {
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), name as CFString, &id)
        if result != kIOReturnSuccess {
            NSLog("MenuStats: power assertion failed (\(result))")
            id = IOPMAssertionID(kIOPMNullAssertionID)
        }
        return result == kIOReturnSuccess
    }

    private func releaseAssertions() {
        releaseAssertion(&systemAssertion)
        releaseAssertion(&displayAssertion)
    }

    private func releaseAssertion(_ id: inout IOPMAssertionID) {
        guard id != IOPMAssertionID(kIOPMNullAssertionID) else { return }
        IOPMAssertionRelease(id)
        id = IOPMAssertionID(kIOPMNullAssertionID)
    }
}

extension Format {
    /// "1:23:45" (hours:minutes:seconds), for the Awake tab.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
    }

    /// "1:23" (hours:minutes), rounded up, for the menu bar.
    static func clockCompact(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
