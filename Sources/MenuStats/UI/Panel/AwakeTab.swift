import AppKit
import SwiftUI

// MARK: - Awake

/// Keep the Mac awake: start a session for a set time, until a download finishes or while an app is open,
/// and choose what stays on.
struct AwakeTab: View {
    var model: AppModel
    @ObservedObject private var awake: AwakeController
    @ObservedObject private var hardware: HardwareControl
    @ObservedObject private var settings = Settings.shared
    @State private var customHours = 0
    @State private var customMinutes = 0

    init(model: AppModel) {
        self.model = model
        self.awake = model.awake
        self.hardware = model.hardware
        let minutes = Settings.shared.awakeCustomMinutes
        _customHours = State(initialValue: minutes / 60)
        _customMinutes = State(initialValue: minutes % 60)
    }

    private var state: AwakeState { awake.state }

    var body: some View {
        VStack(spacing: 8) {
            statusCard
            durationCard
            customCard
            untilCard
            aiCard
            optionsCard
            detailsCard
        }
    }

    // MARK: Cards

    private var statusCard: some View {
        Card {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .center) {
                    Hero(value: heroValue(at: context.date), caption: heroCaption, accent: state.isActive ? Palette.color(3) : nil)
                    Spacer()
                    Image(systemName: state.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 26))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(state.isActive ? Palette.color(3) : Color.secondary)
                }
            }
            if state.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let fraction = barFraction(context.date) {
                        UsageBar(fraction: fraction, color: Palette.color(3), height: 7)
                    }
                }
                Button(role: .destructive) { awake.stop() } label: {
                    Label("Termina la sessione", systemImage: "stop.circle")
                }
                .buttonStyle(.link).font(.system(size: 12))
            } else if let reason = awake.lastEndReason {
                Label("Sessione terminata: \(reason)", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var durationCard: some View {
        Card(title: state.isActive ? "Cambia durata" : "Avvia per") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(AwakeController.durations, id: \.label) { duration in
                    Button { awake.start(minutes: duration.minutes) } label: { capsule(duration.label) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// Hours and minutes of the user's choice; remembered for next time.
    private var customCard: some View {
        Card(title: "Durata personalizzata") {
            HStack(spacing: 10) {
                Stepper(value: $customHours, in: 0...99) {
                    Text("\(customHours) h").monospacedDigit().frame(width: 38, alignment: .trailing)
                }
                Stepper(value: $customMinutes, in: 0...59, step: 5) {
                    Text("\(customMinutes) min").monospacedDigit().frame(width: 50, alignment: .trailing)
                }
                Spacer()
                Button { start(custom: customHours * 60 + customMinutes) } label: { capsule("Avvia", wide: false) }
                    .buttonStyle(.plain)
                    .disabled(customHours * 60 + customMinutes == 0)
            }
            .font(.system(size: 12))
            .controlSize(.small)
        }
    }

    /// Sessions that end on their own: when a download stops growing, or when an app quits.
    private var untilCard: some View {
        Card(title: "Finché…") {
            HStack {
                Label("un file si sta scaricando", systemImage: "arrow.down.circle")
                Spacer()
                Button { chooseFile() } label: { capsule("Scegli file…", wide: false) }.buttonStyle(.plain)
            }
            HStack {
                Text("Fermo da").foregroundStyle(.secondary)
                Picker("", selection: $settings.awakeDownloadTimeout) {
                    ForEach(AwakeController.downloadTimeouts, id: \.seconds) { Text($0.label).tag($0.seconds) }
                }
                .labelsHidden().fixedSize().controlSize(.small)
                Text("= finito").foregroundStyle(.secondary)
                Spacer()
            }
            .font(.system(size: 11.5))
            Divider()
            HStack {
                Label("un'app è aperta", systemImage: "app.badge.checkmark")
                Spacer()
                Menu {
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") { awake.start(whileRunning: app) }
                    }
                } label: { capsule("Scegli app…", wide: false) }
                    .buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
        }
        .font(.system(size: 12))
    }

    /// A persistent switch: while any AI tool reports it is working, the Mac stays awake, then it lets go by itself.
    private var aiCard: some View {
        Card(title: "Intelligenza artificiale") {
            Toggle(isOn: Binding(get: { settings.awakeWatchAI }, set: { awake.setWatchAI($0) })) {
                Label("Sveglio finché l'IA lavora", systemImage: "sparkles")
            }
            .toggleStyle(.trailingSwitch).controlSize(.small)
            Text(aiCaption).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aiCaption: String {
        guard settings.awakeWatchAI else {
            return "Riconosce da solo Claude Code, Codex, Gemini CLI e OpenCode al lavoro e tiene sveglio il Mac finché finiscono."
        }
        if case .ai = state.kind, state.isActive {
            return "\(AwakeController.describe(state.aiTools)): il Mac resta sveglio finché il lavoro non finisce."
        }
        return "In attesa: il Mac resta sveglio appena Claude Code, Codex o un'altra IA inizia a lavorare."
    }

    private var optionsCard: some View {
        Card(title: "Opzioni") {
            Toggle(isOn: Binding(get: { state.isActive ? state.allowsDisplaySleep : settings.awakeAllowDisplaySleep }, set: { awake.setAllowDisplaySleep($0) })) {
                Label("Lascia spegnere lo schermo", systemImage: "display")
            }
            .toggleStyle(.trailingSwitch).controlSize(.small)
            if HardwarePresence.hasBattery {
                Toggle(isOn: Binding(get: { settings.awakeLidClosed }, set: { awake.setLidClosed($0) })) {
                    Label("Sveglio anche col coperchio chiuso", systemImage: "laptopcomputer")
                }
                .toggleStyle(.trailingSwitch).controlSize(.small)
                .disabled(!hardware.canUseHelper && !settings.awakeLidClosed)
                if let lidCaption {
                    Text(lidCaption).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Toggle(isOn: $settings.awakeEndOnLowBattery) {
                    Label("Termina sotto il \(Format.percent(settings.awakeLowBatteryThreshold)) di batteria", systemImage: "battery.25percent")
                }
                .toggleStyle(.trailingSwitch).controlSize(.small)
            }
        }
    }

    private var detailsCard: some View {
        Card(title: "Dettagli") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                StatGrid(items: [
                    ("Stato", state.isActive ? "Attivo" : "Spento"),
                    ("Schermo", !state.isActive ? "—" : (state.allowsDisplaySleep ? "Può spegnersi" : "Resta acceso")),
                    ("Coperchio chiuso", !state.isActive || !HardwarePresence.hasBattery ? "—" : (hardware.lidAwake ? "Resta sveglio" : "Va in stop")),
                    ("Avviata alle", state.startDate.map { DateText.string($0, settings.use24Hour ? "HH:mm" : "h:mm a") } ?? "—"),
                    ("Termina", endText),
                    ("In corso da", state.startDate.map { Format.clock(context.date.timeIntervalSince($0)) } ?? "—"),
                ])
            }
        }
    }

    /// Why lid-closed awake is off or what it implies; nil when there is nothing to add.
    private var lidCaption: String? {
        if !hardware.canUseHelper {
            return "Serve l'helper con privilegi: si installa da Impostazioni ▸ Sveglio."
        }
        guard settings.awakeLidClosed else { return nil }
        if let error = hardware.lidError { return error }
        let screen = "Chiudendo il coperchio lo schermo si spegne subito, il Mac continua a lavorare."
        if hardware.lidAwake { return screen + " Anche Stop dal menu Apple è sospeso finché dura la sessione." }
        return state.isActive ? screen : screen + " Vale per la prossima sessione."
    }

    // MARK: Actions

    private func start(custom minutes: Int) {
        settings.awakeCustomMinutes = minutes
        awake.start(minutes: minutes)
    }

    /// A file picker; hidden files stay visible because many browsers name partial downloads ".something.part".
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Scegli il file in download"
        panel.prompt = "Controlla"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true // Safari's ".download" is a package
        panel.treatsFilePackagesAsDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            awake.start(watching: url, timeout: settings.awakeDownloadTimeout)
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    // MARK: Text

    private var endText: String {
        guard state.isActive else { return "—" }
        switch state.kind {
        case .timed:
            return state.endDate.map { DateText.string($0, settings.use24Hour ? "HH:mm" : "h:mm a") } ?? "Mai"
        case .download: return "Download finito"
        case .app: return "App chiusa"
        case .ai: return "Quando l'IA finisce"
        }
    }

    private func heroValue(at date: Date) -> String {
        guard state.isActive else { return "Spento" }
        switch state.kind {
        case .timed: return state.remaining(at: date).map(Format.clock) ?? "∞"
        case .download(_, let progress): return progress.map { Format.percent($0) } ?? "In corso"
        case .app: return "App aperta"
        case .ai: return "IA al lavoro"
        }
    }

    private var heroCaption: String {
        guard state.isActive else {
            return settings.awakeWatchAI ? "In attesa che l'IA lavori" : "Il Mac può andare in stop"
        }
        switch state.kind {
        case .timed:
            return state.endDate == nil ? "Il Mac resta sveglio finché non termini" : "Il Mac resta sveglio · tempo rimanente"
        case .download(let name, _): return "Sveglio finché «\(Format.truncated(name, to: 28))» si scarica"
        case .app(let name): return "Sveglio finché \(Format.truncated(name, to: 26)) è aperta"
        case .ai(let working): return working == 1 ? "Sveglio finché l'IA non ha finito" : "Sveglio finché le \(working) sessioni non finiscono"
        }
    }

    /// The bar fills with the remaining time, or with the download progress when macOS reports one.
    private func barFraction(_ date: Date) -> Double? {
        switch state.kind {
        case .timed:
            guard let end = state.endDate, let start = state.startDate else { return nil }
            return max(end.timeIntervalSince(date), 0) / max(end.timeIntervalSince(start), 1)
        case .download(_, let progress): return progress
        case .app, .ai: return nil
        }
    }

    private func capsule(_ title: String, wide: Bool = true) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .medium))
            .frame(maxWidth: wide ? .infinity : nil)
            .padding(.horizontal, wide ? 0 : 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Palette.color(3).opacity(0.22)))
            .foregroundStyle(Color.primary)
            .contentShape(Capsule())
    }
}
