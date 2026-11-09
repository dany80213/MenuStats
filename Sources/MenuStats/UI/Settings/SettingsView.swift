import AppKit
import ServiceManagement
import SwiftUI

enum SettingsPage: Hashable, Identifiable {
    case general, menubar, module(ModuleID), map, widgets, updates, notifications, about
    var id: Self { self }

    var title: String {
        switch self {
        case .general: "Generale"
        case .menubar: "Barra dei menu"
        case .module(let module): module.name
        case .widgets: "Widget"
        case .updates: "Aggiornamenti"
        case .map: "Mappa"
        case .notifications: "Notifiche"
        case .about: "Info"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .menubar: "menubar.rectangle"
        case .module(let module): module.symbol
        case .widgets: "square.grid.2x2"
        case .updates: "arrow.down.circle"
        case .map: "map"
        case .notifications: "bell.badge"
        case .about: "info.circle"
        }
    }
}

/// The page the settings window shows; set before opening it to jump to a page (e.g. from the dropdown).
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var page: SettingsPage? = .general
}

struct SettingsView: View {
    var model: AppModel
    @ObservedObject var feed: SlowFeed
    @ObservedObject var settings: Settings

    init(model: AppModel, settings: Settings) {
        self.model = model
        self.feed = model.slowFeed
        self.settings = settings
    }
    @ObservedObject private var navigation = SettingsNavigation.shared
    private var page: SettingsPage? { navigation.page }

    var body: some View {
        NavigationSplitView {
            // The quit button sits below the list, not over it: an inset floats over the sidebar's glass and the
            // list scrolls underneath it, so the last rows showed through the button.
            VStack(spacing: 0) {
                List(selection: $navigation.page) {
                    Section {
                        row(.general)
                        row(.menubar)
                    }
                    Section("Moduli") {
                        ForEach(ModuleID.allCases.filter { $0.isAvailable || $0 == .fans }) { row(.module($0)) }
                    }
                    Section {
                        row(.widgets)
                        row(.updates)
                        row(.map)
                        row(.notifications)
                        row(.about)
                    }
                }
                Divider()
                Button(role: .destructive) { NSApp.terminate(nil) } label: {
                    Label("Esci da MenuStats", systemImage: "power").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .padding(10)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            ScrollView {
                detail
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(page?.title ?? "")
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private func row(_ page: SettingsPage) -> some View {
        Label(page.title, systemImage: page.symbol).tag(page)
    }

    @ViewBuilder private var detail: some View {
        switch page ?? .general {
        case .general: GeneralSettings(settings: settings, today: model.weather.report?.today, model: model, snapshot: feed.snapshot)
        case .menubar: MenubarSettings(model: model, snapshot: feed.snapshot, settings: settings)
        case .module(let module): ModuleSettings(module: module, model: model, snapshot: feed.snapshot, settings: settings)
        case .widgets: WidgetSettings(model: model)
        case .updates: UpdateSettings(updater: model.updater)
        case .map: MapSettings(settings: settings)
        case .notifications: NotificationSettings(settings: settings)
        case .about: AboutSettings(model: model)
        }
    }
}

// MARK: - Shared pieces

struct SettingsSection<Content: View>: View {
    var title: String
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
            if let footnote {
                Text(footnote).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 18)
    }
}

/// A menu bar image shown on light and dark strips, like the real menu bar.
struct MenubarPreview: View {
    var image: NSImage
    /// Stack the light and dark strips for wide images (the full menu bar).
    var vertical = false

    var body: some View {
        if vertical {
            VStack(alignment: .leading, spacing: 6) { strip(dark: false); strip(dark: true) }
        } else {
            HStack(spacing: 8) { strip(dark: false); strip(dark: true) }
        }
    }

    private func strip(dark: Bool) -> some View {
        Image(nsImage: MenubarRenderer.rasterize(image, dark: dark))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(dark ? Color(white: 0.16) : Color(white: 0.93)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
    }
}

/// Radio list of styles, each with a live preview of how it looks in the menu bar.
struct StylePicker<Option: StyleOption>: View {
    @Binding var selection: Option
    var preview: (Option) -> NSImage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(Option.allCases), id: \.self) { option in
                Button { selection = option } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selection == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selection == option ? Color.accentColor : Color.secondary)
                        Text(option.label).frame(width: 190, alignment: .leading)
                        MenubarPreview(image: preview(option))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Pages

struct GeneralSettings: View {
    @ObservedObject var settings: Settings
    /// Sunrise and sunset for "Alba e tramonto", when the Weather module knows them.
    var today: WeatherReport.Day? = nil
    /// For the menu bar preview of the color presets.
    var model: AppModel? = nil
    var snapshot: Snapshot? = nil
    @State private var loginEnabled = LoginItem.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeneralHero(settings: settings)
            SettingsSection(title: "Colori", footnote: "Un preset cambia tutti i colori insieme: le schede della tendina, i grafici di rete e disco e le icone nella barra. Passa sopra a un preset per vederlo, fai clic per applicarlo. Poi puoi cambiare ogni colore dalla pagina del suo modulo.") {
                ColorPresetPicker(settings: settings, menubar: menubarPreview)
            }
            SettingsSection(title: "Aspetto", footnote: "Vale per la tendina e per questa finestra; le icone nella barra dei menu seguono macOS. Come macOS segue Impostazioni di Sistema ▸ Aspetto (anche quando lì è su Automatico). Alba e tramonto è l'orario di MenuStats: scura dal tramonto all'alba della città del Meteo, oppure dalle 20 alle 7 se il Meteo è spento. Sfondo pieno toglie la trasparenza, così le scritte restano leggibili su qualsiasi sfondo. Puoi cambiare entrambi anche dal pulsante in fondo alla tendina.") {
                AppearancePicker(settings: settings)
                Picker("Sfondo della tendina", selection: $settings.panelBackground) {
                    ForEach(PanelBackground.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                if settings.appearanceMode == .automatic {
                    Text(AppearanceController.scheduleDescription(today: today, now: Date()))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            SettingsSection(title: "Aggiornamento") {
                Picker("Intervallo di aggiornamento", selection: $settings.refreshInterval) {
                    Text("1 secondo").tag(1.0)
                    Text("2 secondi").tag(2.0)
                    Text("3 secondi").tag(3.0)
                    Text("5 secondi").tag(5.0)
                }
                .frame(width: 340)
                Picker("Unità di temperatura", selection: $settings.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 340)
            }
            SettingsSection(title: "Processi", footnote: "Senza privilegi di amministratore si vedono solo i processi del tuo utente.") {
                Stepper("Processi mostrati: \(settings.processCount)", value: $settings.processCount, in: 3...12)
                Toggle("Raggruppa i processi per app (es. tutti gli helper di Chrome insieme)", isOn: $settings.groupProcessesByApp)
            }
            SettingsBackupSection()
            SettingsSection(title: "Avvio", footnote: LoginItem.isAvailable ? nil : "Disponibile solo per l'app installata con scripts/install.sh.") {
                Toggle("Apri MenuStats al login", isOn: Binding(get: { loginEnabled }, set: { enabled in
                    LoginItem.setEnabled(enabled)
                    loginEnabled = LoginItem.status == .enabled
                }))
                .disabled(!LoginItem.isAvailable)
                if LoginItem.status == .requiresApproval {
                    Text("Da autorizzare in Impostazioni di Sistema ▸ Generali ▸ Elementi login.")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
        }
    }
}

/// Export to / import from a file, e.g. to bring the same setup to another Mac.
extension GeneralSettings {
    /// The menu bar with the enabled modules, icons tinted with the given colors.
    var menubarPreview: (([ModuleID: NSColor]) -> NSImage)? {
        guard let model, let snapshot else { return nil }
        return { colors in
            var options = MenubarOptions(settings)
            options.colorIcons = true
            options.severityColors = false
            options.moduleColors = colors
            let context = MenubarRenderer.Context(snapshot: snapshot, options: options,
                                                  recent: { model.recentValues($0, count: $1) },
                                                  weather: model.weather.report, weatherConfigured: settings.weatherLocation != nil,
                                                  awake: model.awake.state)
            return MenubarRenderer.image(for: settings.visibleModules, context: context).image
        }
    }
}

struct SettingsBackupSection: View {
    @State private var message: String?

    var body: some View {
        SettingsSection(title: "Backup delle impostazioni",
                        footnote: "Salva in un file tutte le scelte di MenuStats (moduli, stili, colori, avvisi, Meteo, Sveglio…) e ripristinale qui o su un altro Mac. Dopo l'importazione MenuStats si riapre. La cronologia dei grafici non è inclusa: si esporta in CSV da Info.") {
            HStack {
                Button("Esporta impostazioni…") { export() }
                Button("Importa impostazioni…") { importBackup() }
                if let message { Text(message).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.propertyList]
        panel.nameFieldStringValue = SettingsBackup.suggestedFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.export(to: url)
            message = "Impostazioni salvate in \(url.lastPathComponent)"
        } catch {
            message = "Salvataggio non riuscito: \(error.localizedDescription)"
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let confirm = NSAlert()
        confirm.messageText = "Importare le impostazioni da \(url.lastPathComponent)?"
        confirm.informativeText = "Le impostazioni attuali verranno sostituite e MenuStats si riaprirà."
        confirm.addButton(withTitle: "Importa e riapri")
        confirm.addButton(withTitle: "Annulla")
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        do {
            try SettingsBackup.importAndRelaunch(from: url)
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Come macOS / Chiara / Scura / Alba e tramonto for MenuStats' windows.
struct AppearancePicker: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Picker("Aspetto", selection: $settings.appearanceMode) {
            ForEach(AppearanceMode.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

/// Every color of one dropdown tab, one picker per palette role.
struct PanelColorSettings: View {
    var tab: DashboardTab
    @ObservedObject var settings: Settings

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(tab.colorRoles, id: \.index) { role in
                ColorPicker(selection: Binding(
                    get: { Palette.color(role.index, in: tab) },
                    set: { settings.setPanelColor(NSColor($0).hexString, tab: tab, role: role.index) }
                ), supportsOpacity: false) {
                    Text(role.name)
                }
            }
        }
        if tab.colorRoles.contains(where: { settings.isCustomPanelColor(tab, $0.index) }) {
            Button("Ripristina i colori della scheda") {
                for role in tab.colorRoles { settings.setPanelColor(nil, tab: tab, role: role.index) }
            }
            .buttonStyle(.link)
        }
    }
}

/// The Map page of Settings: a large map with this Mac's position and its color.
struct MapSettings: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Posizione", footnote: "La posizione viene chiesta a macOS solo con questa pagina o la scheda Mappa aperte. Le posizioni di Dov'è (iPhone, AirTag, amici) non sono accessibili ad altre app.") {
                MapTab(mapHeight: 360)
            }
            NearbyDevicesSettings(settings: settings)
            SettingsSection(title: "Colore") {
                PanelColorSettings(tab: .map, settings: settings)
            }
        }
    }
}

/// Options for the nearby-devices card and the proximity lock, on the Map page of Settings.
struct NearbyDevicesSettings: View {
    @ObservedObject var settings: Settings
    @State private var known: [NearbyDeviceReader.Entry] = []
    @State private var confirmingTest = false

    private static let graceOptions: [(label: String, seconds: Int)] = [
        ("2 secondi", 2), ("5 secondi", 5), ("10 secondi", 10), ("15 secondi", 15), ("30 secondi", 30),
        ("1 minuto", 60), ("2 minuti", 120), ("5 minuti", 300),
    ]

    var body: some View {
        SettingsSection(title: "Dispositivi vicini",
                        footnote: "Il radar è il disegno con gli anelli a 1, 3 e 10 metri; l'elenco con le distanze resta comunque. Si vedono solo i dispositivi che macOS già conosce, mai quelli di altre persone.") {
            Toggle("Mostra il radar nella scheda Mappa", isOn: $settings.nearbyShowRadar)
        }
        SettingsSection(title: "Blocca il Mac se mi allontano",
                        footnote: "Funziona sempre, a scheda chiusa, finché è acceso: MenuStats legge i dispositivi ogni pochi secondi (da 1 a 60, secondo il tempo scelto), a costo quasi nullo. Un dispositivo conta solo dopo che è stato visto, così l'opzione non scatta se il telefono è in un'altra stanza quando la accendi. Dopo il blocco non scatta di nuovo finché un dispositivo scelto non torna vicino. Cuffie e AirPods spesso spariscono dal segnale quando li metti nella custodia: meglio scegliere iPhone o Apple Watch. È una comodità, non una sicurezza: il segnale Bluetooth può restare anche a distanza o sparire per un attimo.") {
            Toggle("Blocca il Mac quando i dispositivi scelti si allontanano", isOn: $settings.proximityLockEnabled)
            if settings.proximityLockEnabled || !settings.proximityLockDevices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dispositivi da controllare").font(.system(size: 12, weight: .medium))
                    ForEach(choices, id: \.id) { entry in
                        Toggle(isOn: binding(for: entry)) {
                            HStack(spacing: 6) {
                                Image(systemName: NearbyMath.symbol(name: entry.name, kind: entry.kind)).frame(width: 16)
                                Text(entry.name).lineLimit(1)
                                if let rssi = entry.rssi {
                                    Text("ora " + NearbyMath.label(forDistance: NearbyMath.distance(rssi: rssi)))
                                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                                } else if !entry.connected {
                                    Text("non nelle vicinanze").font(.system(size: 10.5)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if choices.isEmpty { Text("Nessun dispositivo Bluetooth noto a questo Mac.").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                if settings.proximityLockDevices.count > 1 {
                    Picker("Blocca quando", selection: $settings.proximityLockRequiresAll) {
                        Text("se ne allontana uno qualsiasi").tag(false)
                        Text("si allontanano tutti").tag(true)
                    }
                }
                Picker("Dopo che non lo sento da", selection: $settings.proximityLockGrace) {
                    ForEach(Self.graceOptions, id: \.seconds) { Text($0.label).tag($0.seconds) }
                }
                if settings.proximityLockGrace <= 5 {
                    Text("Con tempi così brevi il Mac può bloccarsi per un calo momentaneo del segnale. macOS aggiorna il segnale di ogni dispositivo solo ogni pochi secondi, quindi non reagisce davvero più in fretta di così.")
                        .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Considera lontano anche oltre una distanza", isOn: $settings.proximityLockUseDistance)
                if settings.proximityLockUseDistance {
                    HStack(spacing: 8) {
                        Text("Distanza massima")
                        TextField("", value: distanceBinding, format: .number.precision(.fractionLength(0...1)))
                            .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width: 60)
                        Text("metri")
                        Stepper("", value: distanceBinding, in: 1...50, step: 0.5).labelsHidden()
                    }
                    Text("La distanza è una stima dal segnale e può sbagliare di diversi metri: guarda il valore \"ora\" accanto a ogni dispositivo, tenendolo dove vuoi che sia il limite, e regola di conseguenza. Il dispositivo conta come lontano solo se resta oltre la distanza per tutto il tempo scelto.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if settings.proximityLockDevices.isEmpty {
                    Text("Scegli almeno un dispositivo, altrimenti il blocco non si attiva.").font(.system(size: 11)).foregroundStyle(.orange)
                }
                HStack {
                    Button("Blocca il Mac ora (prova)") { confirmingTest = true }
                    Text("Serve a vedere che il blocco funziona su questo Mac.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { loadKnown() }
        .confirmationDialog("Bloccare il Mac adesso?", isPresented: $confirmingTest) {
            Button("Blocca ora") { SystemActions.lockScreen() }
            Button("Annulla", role: .cancel) {}
        } message: { Text("Dovrai sbloccarlo con la password o Touch ID.") }
    }

    /// Known devices, plus chosen ones that macOS no longer lists, so they can still be switched off.
    private var choices: [NearbyDeviceReader.Entry] {
        let listed = Set(known.map(\.id))
        let missing = settings.proximityLockDevices.filter { !listed.contains($0.key) }
            .map { NearbyDeviceReader.Entry(id: $0.key, name: $0.value, kind: nil, connected: false, rssi: nil) }
        return (known + missing).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Meters typed by hand, kept between 1 and 50.
    private var distanceBinding: Binding<Double> {
        Binding(get: { settings.proximityLockDistance },
                set: { settings.proximityLockDistance = min(max($0, 1), 50) })
    }

    private func binding(for entry: NearbyDeviceReader.Entry) -> Binding<Bool> {
        Binding(get: { settings.proximityLockDevices[entry.id] != nil },
                set: { on in
                    if on { settings.proximityLockDevices[entry.id] = entry.name } else { settings.proximityLockDevices[entry.id] = nil }
                })
    }

    private func loadKnown() {
        DispatchQueue.global(qos: .utility).async {
            let entries = NearbyDeviceReader.sample()
            DispatchQueue.main.async { known = entries }
        }
    }
}

struct MenubarSettings: View {
    var model: AppModel
    var snapshot: Snapshot
    @ObservedObject var settings: Settings

    var body: some View {
        let context = MenubarRenderer.Context(snapshot: snapshot, options: MenubarOptions(settings),
                                              recent: { model.recentValues($0, count: $1) },
                                              weather: model.weather.report, weatherConfigured: settings.weatherLocation != nil,
                                              awake: model.awake.state)
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Anteprima") {
                MenubarPreview(image: MenubarRenderer.image(for: settings.visibleModules, context: context).image, vertical: true)
            }
            SettingsSection(title: "Moduli", footnote: "Trascina per cambiare l'ordine. In modalità separata puoi anche ⌘-trascinare le voci nella barra.") {
                List {
                    ForEach(settings.moduleOrder) { module in
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Toggle(isOn: Binding(get: { settings.isEnabled(module) }, set: { settings.setEnabled(module, $0) })) {
                                Label(module.name, systemImage: module.symbol).frame(width: 130, alignment: .leading)
                            }
                            .disabled(!module.isAvailable)
                            if !module.isAvailable {
                                Text(module == .fans ? "Questo Mac non ha ventole" : "Non disponibile su questo Mac")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            MenubarPreview(image: MenubarRenderer.image(for: [module], context: context).image)
                                .opacity(settings.isEnabled(module) ? 1 : 0.4)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { settings.moduleOrder.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(height: CGFloat(settings.moduleOrder.count) * 40 + 8)
                .scrollDisabled(true)
            }
            SettingsSection(title: "Spazio nella barra", footnote: "Su macOS 27, quando accanto al notch non c'è spazio, macOS raccoglie le icone dietro la freccia «, partendo da quelle più lontane dall'orologio. Tenendo MenuStats accanto all'orologio sono le icone delle altre app a finire dietro la freccia. Se lo spazio non basta comunque, MenuStats toglie prima le etichette e poi gli ultimi moduli dell'elenco Moduli qui sopra, e torna completo appena lo spazio si libera.") {
                Toggle("Tieni MenuStats accanto all'orologio", isOn: $settings.pinNearClock)
                Toggle("Riduci automaticamente quando lo spazio non basta", isOn: $settings.autoFitMenubar)
                Divider()
                Toggle("Barra compatta sempre attiva", isOn: $settings.compactMenubar)
                Stepper("Moduli mostrati: \(settings.compactModuleCount)", value: $settings.compactModuleCount, in: 1...6)
                    .disabled(!settings.compactMenubar)
            }
            SettingsSection(title: "Aspetto") {
                Picker("Disposizione", selection: $settings.layout) {
                    ForEach(MenubarLayout.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Toggle("Mostra le etichette sopra i valori (CPU, MEM, …)", isOn: $settings.showLabels)
                Toggle("Larghezza che si adatta al valore", isOn: $settings.menubarDynamicWidth)
                Text(settings.menubarDynamicWidth
                     ? "Ogni modulo occupa solo lo spazio che serve adesso: «5%» è più stretto di «100%». Quando il numero cresce, il modulo si allarga."
                     : "Ogni modulo tiene sempre lo spazio del valore più lungo (per esempio «100%»): niente si sposta, ma resta spazio vuoto.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Spazio tra i moduli")
                    Slider(value: $settings.menubarSpacing, in: 2...20, step: 1).frame(width: 200)
                    Text("\(Int(settings.menubarSpacing)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                }
                if settings.layout == .separate {
                    Text("Con una voce per modulo lo spazio fra le voci lo decide macOS: lo spazio scelto qui vale per la voce unica.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Icone dinamiche: cambiano in base a cosa fa il Mac", isOn: $settings.dynamicIcons)
                if settings.dynamicIcons {
                    Text("Ventola che gira quando le ventole sono attive · fiamma con CPU sotto carico · termometro che sale e avviso di rallentamento termico · frecce di rete e disco accese solo con traffico · batteria con fulmine, spina o foglia (basso consumo) · avviso con pressione di memoria alta.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if HardwarePresence.hasFans {
                        Picker("Ventola che gira", selection: $settings.iconAnimation) {
                            ForEach(IconAnimation.allCases) { Text($0.label).tag($0) }
                        }
                        .frame(width: 420)
                        Text("Ogni fotogramma è un'immagine nuova per la barra dei menu, 12 al secondo: mentre le ventole girano MenuStats usa circa il 13% di un core, contro l'1% con la ventola ferma. Con la modalità basso consumo si ferma sempre. La tazza di Sveglio non si muove: mostra il vapore fermo.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            SettingsSection(title: "Colori", footnote: "Le soglie di allerta: CPU e temperatura seguono le soglie delle rispettive pagine; memoria in base alla pressione; disco sotto il 15/10/5% libero; ventole oltre il 35/60/85% della velocità massima; batteria sotto il 30/20/10% (verde mentre è in carica).") {
                Toggle("Colori di allerta automatici: giallo → arancione → rosso quando serve attenzione", isOn: $settings.severityColors)
                Toggle("Colora le icone con un colore per modulo", isOn: $settings.colorIcons)
                if settings.colorIcons {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(ModuleID.available) { module in
                            ModuleColorPicker(module: module, settings: settings)
                        }
                    }
                    Button("Ripristina colori predefiniti") { settings.moduleColors = Settings.defaultColors }
                        .buttonStyle(.link)
                }
            }
        }
    }
}

struct ModuleSettings: View {
    var module: ModuleID
    var model: AppModel
    var snapshot: Snapshot
    @ObservedObject var settings: Settings

    private func preview(_ change: (inout MenubarOptions) -> Void) -> NSImage {
        var options = MenubarOptions(settings)
        change(&options)
        let context = MenubarRenderer.Context(snapshot: snapshot, options: options,
                                              recent: { model.recentValues($0, count: $1) },
                                              weather: model.weather.report, weatherConfigured: settings.weatherLocation != nil,
                                              awake: module == .awake ? .sample : model.awake.state)
        return MenubarRenderer.image(for: [module], context: context).image
    }

    var body: some View {
        if module == .fans && !HardwarePresence.hasFans {
            noFans
        } else {
            moduleBody
        }
    }

    /// Fanless Macs (MacBook Air): nothing to configure, so say why instead of showing dead controls.
    private var noFans: some View {
        SettingsSection(title: "Ventole non disponibili",
                        footnote: "Il controllo delle ventole, l'helper con privilegi e gli avvisi sulla velocità sono disattivati perché non c'è nulla da controllare. Le temperature restano disponibili nel modulo Temperature.") {
            Label("Questo Mac non ha ventole", systemImage: "fan.slash").font(.system(size: 13, weight: .medium))
            Text("MenuStats ha rilevato che questo modello (per esempio un MacBook Air) è raffreddato in modo passivo, senza ventole.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var colorFootnote: String {
        var text = "I colori della scheda \(module.tab.title) nella tendina: grafici, barre e icone."
        if module == .network || module == .disk {
            text += " \(module == .network ? "Download e upload" : "Lettura e scrittura") sono gli stessi dei grafici nella barra dei menu."
        }
        return text + " Il colore della voce nella barra dei menu si sceglie sopra, con «Colora l'icona»."
    }

    private var moduleBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Barra dei menu") {
                Toggle("Mostra \(module.name) nella barra dei menu",
                       isOn: Binding(get: { settings.isEnabled(module) }, set: { settings.setEnabled(module, $0) }))
                Toggle("Colora l'icona", isOn: $settings.colorIcons)
                if settings.colorIcons { ModuleColorPicker(module: module, settings: settings) }
                let severity = Severity.of(module, snapshot: snapshot, cpuBusy: settings.cpuBusyThreshold,
                                           temperatureHot: settings.temperatureHotThreshold, source: settings.sensorSource)
                HStack(spacing: 6) {
                    Circle().fill(severity.color ?? Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                    Text("Stato attuale: \(severity.label)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            SettingsSection(title: "Stile") { stylePicker }
            SettingsSection(title: "Colori nella tendina", footnote: colorFootnote) {
                PanelColorSettings(tab: module.tab, settings: settings)
            }
            let sections = PanelSection.allCases.filter { $0.module == module }
            if !sections.isEmpty {
                SettingsSection(title: "Sezioni nella tendina",
                                footnote: "Le sezioni nascoste non vengono nemmeno misurate: MenuStats lavora meno. Puoi nasconderle anche dalla tendina con clic destro.") {
                    ForEach(sections) { section in
                        Toggle(isOn: Binding(get: { settings.shows(section) }, set: { settings.setShown(section, $0) })) {
                            HStack(spacing: 6) {
                                Text(section.title)
                                if let saving = section.saving {
                                    Text("nascosta: \(saving)").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            extra
        }
    }

    @ViewBuilder private var stylePicker: some View {
        switch module {
        case .cpu: StylePicker(selection: $settings.cpuStyle) { style in preview { $0.cpuStyle = style } }
        case .memory: StylePicker(selection: $settings.memoryStyle) { style in preview { $0.memoryStyle = style } }
        case .disk: StylePicker(selection: $settings.diskStyle) { style in preview { $0.diskStyle = style } }
        case .network: StylePicker(selection: $settings.networkStyle) { style in preview { $0.networkStyle = style } }
        case .sensors: StylePicker(selection: $settings.sensorSource) { source in preview { $0.sensorSource = source } }
        case .fans: StylePicker(selection: $settings.fanStyle) { style in preview { $0.fanStyle = style } }
        case .battery: StylePicker(selection: $settings.batteryStyle) { style in preview { $0.batteryStyle = style } }
        case .weather: StylePicker(selection: $settings.weatherStyle) { style in preview { $0.weatherStyle = style } }
        case .date: StylePicker(selection: $settings.dateStyle) { style in preview { $0.dateStyle = style } }
        case .awake: StylePicker(selection: $settings.awakeStyle) { style in preview { $0.awakeStyle = style } }
        }
    }

    @ViewBuilder private var extra: some View {
        switch module {
        case .cpu:
            SettingsSection(title: "Icona dinamica", footnote: "Sopra questa soglia compare una fiamma e il valore diventa in grassetto.") {
                ThresholdSlider(title: "CPU sotto carico oltre", value: $settings.cpuBusyThreshold, range: 0.5...1, step: 0.05,
                                format: Format.percent)
            }
        case .sensors:
            SettingsSection(title: "Icona dinamica", footnote: "Il termometro sale con la temperatura; sopra la soglia il valore va in grassetto. Se macOS rallenta il Mac per il calore compare il termometro con il sole.") {
                ThresholdSlider(title: "Temperatura alta oltre", value: $settings.temperatureHotThreshold, range: 60...100, step: 1,
                                format: { Format.temperature($0) })
            }
        case .fans:
            SettingsSection(title: "Ventole", footnote: "Personalizzato fissa la velocità fra il minimo e il massimo di fabbrica. Le ventole tornano in automatico quando MenuStats si chiude, va in crash, il Mac va in stop o macOS segnala stress termico.") {
                ForEach(snapshot.smc?.fans ?? []) { fan in FanRow(fan: fan, hardware: model.hardware) }
                if (snapshot.smc?.fans ?? []).isEmpty { Text("Nessuna ventola rilevata").foregroundStyle(.secondary) }
            }
            HelperSettings(hardware: model.hardware)
        case .battery:
            SettingsSection(title: "Batteria", footnote: "Il limite di carica è quello di macOS (Impostazioni Batteria ▸ Limite di carica): lo applica il sistema anche in stop e dopo il riavvio, e non richiede l'helper. La modalità basso consumo si cambia dalla scheda Batteria: macOS chiede la password di amministratore.") {
                ChargeLimitPicker(hardware: model.hardware)
                if !model.hardware.chargeLimitSupported { Text("Limite di carica non disponibile su questo Mac").foregroundStyle(.secondary) }
                Button("Apri Impostazioni Batteria…") { SystemActions.openBatterySettings() }
            }
        case .date:
            SettingsSection(title: "Formato") {
                Toggle("Formato 24 ore", isOn: $settings.use24Hour)
            }
            CalendarSettings(model: model, calendar: model.calendar, settings: settings)
        case .disk:
            GraphColorSettings(settings: settings, series: [.write, .read], enabled: settings.diskStyle.usesGraphs)
        case .network:
            GraphColorSettings(settings: settings, series: [.upload, .download], enabled: settings.networkStyle.usesGraphs)
            SettingsSection(title: "IP pubblico e VPN",
                            footnote: "L'IP pubblico si legge da ipwho.is (e l'IPv4, se il Mac usa IPv6, da api4.ipify.org), gratuiti e senza account: MenuStats fa una richiesta solo quando la scheda Rete è aperta, al massimo ogni 5 minuti o quando cambiano rete o VPN. È spento finché non lo attivi. Lo stato della VPN e il suo IP si leggono sul Mac, senza richieste. Con una VPN attiva l'IP pubblico è quello d'uscita della VPN, e la bandiera accanto all'IP della VPN è quella del paese di quell'indirizzo: per mostrarla, a VPN attiva, MenuStats fa la stessa richiesta anche se l'IP pubblico è spento.") {
                Toggle("Mostra l'IP pubblico", isOn: $settings.publicIPEnabled)
                Toggle("Mostra la bandiera del paese", isOn: $settings.showCountryFlag).disabled(!settings.publicIPEnabled)
                Toggle("Mostra anche l'IPv6", isOn: $settings.showIPv6).disabled(!settings.publicIPEnabled)
                Toggle("Mostra se c'è una VPN e il suo IP", isOn: $settings.showVPN)
                Toggle("Mostra la bandiera accanto all'IP della VPN", isOn: $settings.showVPNCountry).disabled(!settings.showVPN)
            }
        case .weather:
            WeatherPlaceSettings(settings: settings, weather: model.weather, location: model.location)
        case .awake:
            AwakeAISettings(model: model, settings: settings)
            if HardwarePresence.hasBattery { AwakeLidSettings(awake: model.awake, hardware: model.hardware, settings: settings) }
            SettingsSection(title: "Sessione",
                            footnote: "Come il comando caffeinate, MenuStats chiede a macOS di non andare in stop per inattività, senza password e senza helper. Una sessione si avvia dalla scheda Sveglio e finisce da sola allo scadere del tempo. Chiudere il coperchio mette il Mac in stop, a meno di attivare l'opzione Coperchio chiuso.") {
                Toggle("Lascia spegnere lo schermo", isOn: Binding(get: { settings.awakeAllowDisplaySleep }, set: { allow in
                    // Timed, download and app sessions; the AI session has its own switch below.
                    if model.awake.state.isActive, !model.awake.state.isAI {
                        model.awake.setAllowDisplaySleep(allow)
                    } else {
                        settings.awakeAllowDisplaySleep = allow
                    }
                }))
                if HardwarePresence.hasBattery {
                    Toggle("Termina la sessione con batteria scarica", isOn: $settings.awakeEndOnLowBattery)
                    ThresholdSlider(title: "Batteria sotto", value: $settings.awakeLowBatteryThreshold, range: 0.05...0.5, step: 0.05,
                                    format: Format.percent)
                        .disabled(!settings.awakeEndOnLowBattery)
                }
            }
        default:
            EmptyView()
        }
    }
}

/// Where the weather comes from: a city searched by hand (Open-Meteo geocoding: only the typed text is sent) or the Mac's position.
struct WeatherPlaceSettings: View {
    @ObservedObject var settings: Settings
    @ObservedObject var weather: WeatherService
    @ObservedObject var location: LocationProvider
    @State private var query = ""
    @State private var results: [WeatherLocation] = []
    @State private var searching = false

    var body: some View {
        SettingsSection(title: "Posizione", footnote: footnote) {
            Picker("Posizione", selection: $settings.weatherLocationMode) {
                ForEach(WeatherLocationMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if settings.weatherLocationMode == .automatic {
                automatic
            } else {
                manual
            }
        }
    }

    private var footnote: String {
        if settings.weatherLocationMode == .automatic {
            return "MenuStats chiede a macOS dove ti trovi (precisione di circa 1 km) e ricava il nome della città con il servizio di Apple. A Open-Meteo vanno solo le coordinate arrotondate. Il rilevamento lavora solo con il modulo Meteo acceso e questa modalità scelta."
        }
        return "I dati arrivano da Open-Meteo (gratuito, senza account). MenuStats invia solo il nome cercato e poi le coordinate della città scelta; con il modulo Meteo spento non fa nessuna richiesta."
    }

    // MARK: - Automatic

    @ViewBuilder private var automatic: some View {
        if let place = location.place {
            placeRow(place, trailing: AnyView(EmptyView()))
        } else if !settings.isEnabled(.weather) {
            HStack {
                Image(systemName: "location.slash").foregroundStyle(.secondary)
                Text("Il rilevamento parte solo con il modulo Meteo acceso.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Accendi Meteo") { settings.setEnabled(.weather, true) }
            }
        } else {
            switch location.status {
            case .waitingForPermission:
                HStack {
                    Image(systemName: "location.circle").foregroundStyle(.secondary)
                    Text("In attesa del permesso: consenti la posizione nella richiesta di macOS. Se non compare, abilita MenuStats nei Servizi di localizzazione.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Apri Impostazioni…") { SystemActions.openLocationSettings() }
                }
            case .denied:
                HStack {
                    Image(systemName: "location.slash").foregroundStyle(.secondary)
                    Text("MenuStats non può usare la posizione. Consentila nei Servizi di localizzazione.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Apri Impostazioni…") { SystemActions.openLocationSettings() }
                }
            case .failed:
                HStack {
                    Image(systemName: "location.slash").foregroundStyle(.secondary)
                    Text("Posizione non disponibile al momento. Riprovo più tardi.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            default:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Rilevo la posizione…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Manual

    @ViewBuilder private var manual: some View {
        if let place = settings.weatherLocation {
            placeRow(place, trailing: AnyView(Button("Rimuovi") { settings.weatherLocation = nil }))
        }
        HStack {
            TextField("Cerca una città (es. Milano)", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit(search)
            Button("Cerca", action: search).disabled(query.trimmingCharacters(in: .whitespaces).count < 2)
            if searching { ProgressView().controlSize(.small) }
        }
        ForEach(results) { place in
            Button {
                settings.weatherLocation = place
                if !settings.isEnabled(.weather) { settings.setEnabled(.weather, true) }
                results = []
                query = ""
            } label: {
                HStack {
                    Text(place.name).font(.system(size: 12.5, weight: .medium))
                    Text(place.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "plus.circle")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func placeRow(_ place: WeatherLocation, trailing: AnyView) -> some View {
        HStack {
            Image(systemName: "location.fill").foregroundStyle(Palette.color(4, in: .map))
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name).font(.system(size: 13, weight: .semibold))
                if !place.detail.isEmpty { Text(place.detail).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer()
            if let report = weather.report {
                Image(systemName: report.condition.symbol).symbolRenderingMode(.multicolor)
                Text(Format.temperature(report.temperature)).monospacedDigit()
            }
            trailing
        }
    }

    private func search() {
        searching = true
        WeatherService.search(query) { places in
            results = places
            searching = false
        }
    }
}

/// The two colors of the network or disk graphs.
struct GraphColorSettings: View {
    @ObservedObject var settings: Settings
    var series: [GraphSeries]
    var enabled: Bool

    var body: some View {
        SettingsSection(title: "Colori dei grafici",
                        footnote: enabled ? "Nel grafico la parte sopra la linea è \(series[0].label.lowercased()), quella sotto \(series[1].label.lowercased()); ognuna ha la sua scala, così anche un traffico piccolo resta visibile."
                                          : "Scegli lo stile \"Grafici\" qui sopra per vedere i due grafici nella barra.") {
            Toggle("Grafici a colori", isOn: $settings.graphColors)
            if settings.graphColors {
                HStack(spacing: 18) {
                    ForEach(series) { item in
                        ColorPicker(selection: Binding(get: { Color(nsColor: settings.color(for: item)) },
                                                       set: { settings.graphSeriesColors[item] = NSColor($0).hexString }),
                                    supportsOpacity: false) { Text(item.label) }
                    }
                    Button("Ripristina") { settings.graphSeriesColors = GraphSeries.defaultColors.filter { series.contains($0.key) }
                        .merging(settings.graphSeriesColors.filter { !series.contains($0.key) }) { a, _ in a } }
                }
            }
        }
    }
}

/// Calendar access, which calendars count, and the menu bar announcements.
struct CalendarSettings: View {
    var model: AppModel
    @ObservedObject var calendar: CalendarService
    @ObservedObject var settings: Settings
    @ObservedObject private var focus = FocusCalendarFilter.shared

    var body: some View {
        SettingsSection(title: "Calendario",
                        footnote: "MenuStats legge i calendari configurati nell'app Calendario del Mac (iCloud, Google, Exchange…) con il permesso di macOS. Gli impegni restano sul Mac: nessun dato esce.") {
            HStack(spacing: 8) {
                Image(systemName: calendar.access == .granted ? "checkmark.circle.fill" : "calendar.badge.exclamationmark")
                    .foregroundStyle(calendar.access == .granted ? Color.green : Color.orange)
                Text(statusText).fixedSize(horizontal: false, vertical: true)
                Spacer()
                switch calendar.access {
                case .notDetermined: Button("Collega il calendario") { calendar.requestAccess() }
                case .denied: Button("Apri Impostazioni di Sistema…") { CalendarService.openPrivacySettings() }
                case .granted: EmptyView()
                }
            }
            Toggle("Mostra gli impegni nella scheda Data", isOn: $settings.calendarEvents)
            if calendar.access == .granted, !calendar.calendars.isEmpty {
                Divider()
                Text("Calendari").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(calendar.calendars) { info in
                    Toggle(isOn: Binding(get: { !settings.hiddenCalendars.contains(info.id) }, set: { shown in
                        if shown { settings.hiddenCalendars.remove(info.id) } else { settings.hiddenCalendars.insert(info.id) }
                    })) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(nsColor: info.color)).frame(width: 9, height: 9)
                            Text(info.title)
                            if !info.source.isEmpty { Text(info.source).font(.system(size: 11)).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        SettingsSection(title: "Full immersion",
                        footnote: "MenuStats usa i filtri Calendario delle tue full immersion (Impostazioni di Sistema ▸ Full immersion ▸ una modalità ▸ Filtri full immersion ▸ Calendario): mentre una è attiva, la scheda Data e gli avvisi nella barra mostrano solo i calendari che quel filtro lascia passare. macOS tiene queste impostazioni protette: per leggerle MenuStats ha bisogno dell'Accesso completo al disco. Le legge soltanto, senza cambiare nulla.") {
            Toggle("Segui la full immersion di macOS", isOn: $settings.calendarFollowFocus)
            if settings.calendarFollowFocus {
                HStack(spacing: 8) {
                    Image(systemName: focusSymbol).foregroundStyle(focusColor)
                    Text(focusStatus).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if focus.status == .noPermission {
                        Button("Apri Accesso completo al disco…") { FocusCalendarFilter.openFullDiskAccessSettings() }
                        Button("Riprova") { focus.refresh(force: true) }
                    } else {
                        Button("Apri Full immersion…") { FocusCalendarFilter.openFocusSettings() }
                    }
                }
            }
        }
        SettingsSection(title: "Avvisi nella barra dei menu",
                        footnote: "Poco prima di un impegno i moduli della barra si fanno da parte e al loro posto compare l'evento: un anello del colore del calendario conta i minuti, sopra il titolo ci sono orario e luogo, e un titolo lungo scorre. Se più impegni cadono insieme, scorrono uno dopo l'altro. Un clic sull'avviso apre la scheda Data su quel giorno. Gli eventi di tutto il giorno non vengono annunciati.") {
            Toggle("Annuncia gli impegni nella barra", isOn: $settings.calendarAlerts)
            Group {
                Picker("Anticipo", selection: $settings.calendarAlertMinutes) {
                    ForEach([1, 2, 5, 10, 15, 20, 30, 45, 60], id: \.self) { Text("\($0) min prima").tag($0) }
                }
                Picker("Durata dell'avviso", selection: $settings.calendarAlertSeconds) {
                    ForEach([4, 6, 8, 10, 15, 20, 30], id: \.self) { Text("\($0) secondi").tag($0) }
                }
                Picker("Ripetizioni", selection: $settings.calendarAlertRepeats) {
                    ForEach(1...5, id: \.self) { Text($0 == 1 ? "Una volta" : "\($0) volte").tag($0) }
                }
                if settings.calendarAlertRepeats > 1 {
                    Picker("Ogni", selection: $settings.calendarAlertRepeatMinutes) {
                        ForEach([1, 2, 3, 5, 10], id: \.self) { Text("\($0) min").tag($0) }
                    }
                }
                Toggle("Annuncia anche quando l'impegno inizia", isOn: $settings.calendarAlertAtStart)
                Button("Prova avviso") { model.eventAlerts.preview(calendar: calendar, settings: settings) }
            }
            .disabled(!settings.calendarAlerts)
            .frame(maxWidth: 360, alignment: .leading)
        }
    }

    private var focusSymbol: String {
        switch focus.status {
        case .noPermission: "lock.fill"
        case .active: "moon.fill"
        case .off, .inactive: "moon"
        }
    }

    private var focusColor: Color {
        switch focus.status {
        case .noPermission: .orange
        case .active: .indigo
        case .off, .inactive: .secondary
        }
    }

    private var focusStatus: String {
        switch focus.status {
        case .off: return ""
        case .noPermission:
            return "MenuStats non può leggere le full immersion: attiva MenuStats in Privacy e sicurezza ▸ Accesso completo al disco."
        case .inactive:
            return "Nessuna full immersion attiva: valgono i calendari scelti qui sopra."
        case .active(let active):
            let names = { (ids: Set<String>) in calendar.calendars.filter { ids.contains($0.id) }.map(\.title) }
            switch active.calendars {
            case nil:
                return "\(active.name) è attiva, senza filtro Calendario: valgono i calendari scelti qui sopra."
            case .show(let ids)?:
                let shown = names(ids)
                return shown.isEmpty ? "\(active.name) è attiva: i calendari del suo filtro non sono su questo Mac."
                    : "\(active.name) è attiva: solo \(shown.joined(separator: ", "))."
            case .hide(let ids)?:
                let visible = CalendarService.visibleCalendarIDs(all: calendar.calendars.map(\.id), hidden: settings.hiddenCalendars,
                                                                 focus: .hide(ids))
                let shown = names(Set(visible))
                return shown.isEmpty ? "\(active.name) è attiva: il suo filtro nasconde tutti i calendari."
                    : "\(active.name) è attiva: solo \(shown.joined(separator: ", "))."
            }
        }
    }

    private var statusText: String {
        switch calendar.access {
        case .granted: "Collegato: \(calendar.calendars.count) calendari."
        case .notDetermined: "Non collegato: MenuStats chiede il permesso all'avvio."
        case .denied: "Accesso negato in Impostazioni di Sistema ▸ Privacy e sicurezza ▸ Calendari."
        }
    }
}

struct ModuleColorPicker: View {
    var module: ModuleID
    @ObservedObject var settings: Settings

    var body: some View {
        ColorPicker(selection: Binding(
            get: { Color(nsColor: settings.color(for: module)) },
            set: { settings.moduleColors[module] = NSColor($0).hexString }
        ), supportsOpacity: false) {
            Label(module.name, systemImage: module.symbol)
        }
    }
}

struct ThresholdSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var format: (Double) -> String

    var body: some View {
        HStack {
            Text(title).frame(width: 190, alignment: .leading)
            Slider(value: $value, in: range, step: step).frame(width: 220)
            Text(format(value)).monospacedDigit().frame(width: 60, alignment: .trailing)
        }
    }
}

struct NotificationSettings: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Avvisi", footnote: "Ogni avviso arriva una volta per episodio (al massimo ogni 10 minuti). Al primo avviso macOS chiede il permesso per le notifiche.") {
                alert("CPU oltre", isOn: $settings.alertCPU, value: $settings.alertCPUThreshold, range: 0.5...1, step: 0.05,
                      format: Format.percent, detail: "per più di 30 secondi")
                alert("Temperatura CPU oltre", isOn: $settings.alertTemperature, value: $settings.alertTemperatureThreshold,
                      range: 60...105, step: 1, format: { Format.temperature($0) })
                alert("Batteria sotto", isOn: $settings.alertBatteryLow, value: $settings.alertBatteryLowThreshold,
                      range: 0.05...0.5, step: 0.05, format: Format.percent, detail: "a batteria")
                alert("Batteria carica al", isOn: $settings.alertBatteryCharged, value: $settings.alertBatteryChargedThreshold,
                      range: 0.5...1, step: 0.05, format: Format.percent, detail: "con l'alimentatore")
                Toggle("Ventole oltre il 70% della velocità massima", isOn: $settings.alertFans)
                    .disabled(!HardwarePresence.hasFans)
                    .help(HardwarePresence.hasFans ? "" : "Questo Mac non ha ventole")
            }
            SettingsSection(title: "Avvisi personalizzati", footnote: "Un'app (con i suoi processi di supporto) che resta sopra la soglia per 2 minuti; la soglia è per core, come in Monitoraggio Attività (100% = un core intero). Lo spazio su disco si controlla ogni 5 minuti. La rete assente avvisa dopo 20 secondi senza connessione.") {
                alert("Un'app usa oltre", isOn: $settings.alertAppCPU, value: $settings.alertAppCPUThreshold, range: 0.3...4, step: 0.1,
                      format: Format.percent, detail: "di CPU per 2 minuti")
                alert("Disco con meno del", isOn: $settings.alertDiskLow, value: $settings.alertDiskLowThreshold, range: 0.02...0.3, step: 0.01,
                      format: Format.percent, detail: "di spazio libero")
                Toggle("Rete assente (nessuna connessione per 20 secondi)", isOn: $settings.alertNetworkDown)
            }
        }
    }

    private func alert(_ title: String, isOn: Binding<Bool>, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                       format: @escaping (Double) -> String, detail: String? = nil) -> some View {
        HStack {
            Toggle(title, isOn: isOn).frame(width: 200, alignment: .leading)
            Slider(value: value, in: range, step: step).frame(width: 180).disabled(!isOn.wrappedValue)
            Text(format(value.wrappedValue)).monospacedDigit().frame(width: 50, alignment: .trailing)
            if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
}

struct AboutSettings: View {
    var model: AppModel
    @State private var cleared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "MenuStats") {
                Text("Monitor di sistema per la barra dei menu.")
                Text("Versione \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "sviluppo")")
                    .foregroundStyle(.secondary)
            }
            SettingsSection(title: "Storico", footnote: "Medie al minuto di tutte le metriche, conservate 8 giorni.") {
                Text(HistoryStore.defaultURL.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting([HistoryStore.defaultURL]) }
                    Button("Esporta CSV…") { exportCSV() }
                    Button("Cancella storico", role: .destructive) {
                        model.history.clear()
                        cleared = true
                    }
                    if cleared { Text("Storico cancellato").foregroundStyle(.secondary) }
                }
                if let exported { Text(exported).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
        }
    }

    @State private var exported: String?

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "MenuStats storico \(Date().formatted(.iso8601.year().month().day())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.history.csv().write(to: url, atomically: true, encoding: .utf8)
            exported = "Storico esportato in \(url.lastPathComponent)"
        } catch {
            exported = "Esportazione non riuscita: \(error.localizedDescription)"
        }
    }
}

/// Install / remove the privileged helper used for fan control.
struct HelperSettings: View {
    @ObservedObject var hardware: HardwareControl

    var body: some View {
        SettingsSection(title: "Helper con privilegi", footnote: "Un piccolo servizio di sistema (LaunchDaemon) scrive la velocità delle ventole nello SMC e tiene sveglio il Mac col coperchio chiuso. Accetta comandi solo da questa copia di MenuStats e rifiuta velocità fuori dai limiti di fabbrica. Dopo l'installazione macOS chiede di consentirlo in Impostazioni di Sistema ▸ Generali ▸ Elementi login.") {
            HStack(spacing: 6) {
                Circle().fill(hardware.helperState == .installed ? Color.green : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                Text("Stato: \(hardware.helperState.label)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                switch hardware.helperState {
                case .unavailable: EmptyView()
                case .notInstalled, .outdated:
                    Button("Installa helper") { hardware.installHelper() }
                case .requiresApproval:
                    Button("Apri Elementi login…") { SMAppService.openSystemSettingsLoginItems() }
                    Button("Controlla di nuovo") { hardware.installHelper() } // after approval, register() loads the job
                    Button("Rimuovi") { hardware.uninstallHelper() }
                case .installed:
                    Button("Ventole in automatico") { hardware.resetFans() }
                    Button("Rimuovi helper") { hardware.uninstallHelper() }
                }
            }
            if let error = hardware.fanError { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
        }
        .onAppear { hardware.refreshHelperState() }
    }
}

/// Lid-closed awake through the root helper, with what it costs and how it is undone.
struct AwakeLidSettings: View {
    let awake: AwakeController
    @ObservedObject var hardware: HardwareControl
    @ObservedObject var settings: Settings

    var body: some View {
        SettingsSection(title: "Coperchio chiuso",
                        footnote: "Durante una sessione l'helper con privilegi disattiva lo stop del Mac, come «sudo pmset disablesleep 1», così puoi chiudere il coperchio e il Mac continua a lavorare. Finché dura, anche Stop dal menu Apple è sospeso. Lo stop torna attivo da solo quando la sessione finisce, quando MenuStats si chiude, va in crash o non risponde per 3 minuti, quando il Mac si scalda troppo, con la batteria sotto il 10% e al riavvio. Se avevi già disattivato lo stop con pmset, MenuStats lo lascia com'è. Non chiudere il Mac acceso in uno zaino: senza aria si scalda.") {
            Toggle("Resta sveglio anche col coperchio chiuso", isOn: Binding(get: { settings.awakeLidClosed }, set: { awake.setLidClosed($0) }))
                .disabled(!hardware.canUseHelper && !settings.awakeLidClosed)
            if !hardware.canUseHelper {
                Text("Serve l'helper con privilegi: installalo qui sotto.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else if let error = hardware.lidError {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        // MacBook Air has no fans, so the helper must be installable from here too.
        if !hardware.canUseHelper { HelperSettings(hardware: hardware) }
    }
}

/// Claude Code's hooks: tell MenuStats exactly when Claude starts and stops working.
private struct ClaudeHooksRow: View {
    @State private var installed = AwakeController.claudeHooksInstalled()
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(installed ? Color.green : Color.orange)
                Text(installed ? "Hook di Claude Code installati: Sveglio si spegne appena Claude finisce."
                               : "Hook di Claude Code non installati: la fine del lavoro di Claude è solo stimata.")
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(installed ? "Rimuovi" : "Installa hook") { set(!installed) }
            }
            Text("Aggiunge a ~/.claude/settings.json gli avvisi di inizio e fine lavoro (il resto del file non cambia; una copia resta in settings.json.menustats-backup). Valgono per Claude Code nel Terminale e nell'app Claude, dalla prossima sessione.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
        }
    }

    private func set(_ install: Bool) {
        do {
            try AwakeController.setClaudeHooks(installed: install)
            error = nil
        } catch {
            self.error = "Impossibile modificare ~/.claude/settings.json: \(error.localizedDescription)"
        }
        installed = AwakeController.claudeHooksInstalled()
    }
}

/// What the AI watcher sees right now.
private struct AIStatusRow: View {
    @ObservedObject var awake: AwakeController

    var body: some View {
        let working: Bool = { if case .ai = awake.state.kind, awake.state.isActive { return true } else { return false } }()
        HStack(spacing: 6) {
            Circle().fill(working ? Color.green : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
            Text(working ? AwakeController.describe(awake.state.aiTools) + ": il Mac resta sveglio." : "Nessuna IA al lavoro in questo momento.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

/// "Stay awake while an AI works": the switch, its options and the hooks that make AI tools report their activity.
struct AwakeAISettings: View {
    var model: AppModel
    @ObservedObject var settings: Settings
    @State private var copied: String?

    var body: some View {
        SettingsSection(title: "Finché l'IA lavora",
                        footnote: "MenuStats riconosce da solo quando Claude Code (anche dentro l'app Claude), Codex, Gemini CLI, OpenCode e altri agenti stanno lavorando: le loro conversazioni vengono salvate a ogni passo e i loro processi, con i comandi che lanciano, usano la CPU. Legge solo le date dei file, mai il contenuto, e nulla esce dal Mac. Il Mac resta sveglio finché c'è attività e si riaddormenta normalmente quando l'IA è ferma da quanto scelto qui sotto.") {
            Toggle("Resta sveglio mentre un'IA lavora", isOn: Binding(get: { settings.awakeWatchAI }, set: { model.awake.setWatchAI($0) }))
            if settings.awakeWatchAI { AIStatusRow(awake: model.awake) }
            Toggle("Lascia spegnere lo schermo in questo caso", isOn: Binding(get: { settings.awakeAIAllowDisplaySleep }, set: { allow in
                // Applies to the AI session running now too, not only to the next one.
                if model.awake.state.isAI {
                    model.awake.setAllowDisplaySleep(allow)
                } else {
                    settings.awakeAIAllowDisplaySleep = allow
                }
            }))
            HStack {
                Text("Considera finito il lavoro dopo")
                Picker("", selection: $settings.awakeAIGraceMinutes) {
                    ForEach([1, 3, 5, 10, 15], id: \.self) { Text("\($0) min senza attività").tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            ClaudeHooksRow()
            DisclosureGroup("Altri strumenti: segnali manuali") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Per strumenti che MenuStats non riconosce: all'inizio del lavoro creano un file in ~/.menustats/ai e alla fine lo cancellano.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Copia comandi generici") {
                            copy("# inizio (e ogni volta che lavora ancora)\n\(AwakeController.aiStartCommand(name: "nome-strumento"))\n# fine\n\(AwakeController.aiStopCommand(name: "nome-strumento"))\n", "comandi")
                        }
                        Button("Apri la cartella") {
                            try? FileManager.default.createDirectory(at: AwakeController.aiDirectory, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(AwakeController.aiDirectory)
                        }
                    }
                    if let copied { Label("Copiati: \(copied)", systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                .padding(.top, 6)
            }
        }
    }

    private func copy(_ text: String, _ what: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = what
    }
}
