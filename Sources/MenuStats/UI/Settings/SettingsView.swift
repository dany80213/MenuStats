import AppKit
import ServiceManagement
import SwiftUI

enum SettingsPage: Hashable, Identifiable {
    case general, menubar, module(ModuleID), notifications, about
    var id: Self { self }

    var title: String {
        switch self {
        case .general: "Generale"
        case .menubar: "Barra dei menu"
        case .module(let module): module.name
        case .notifications: "Notifiche"
        case .about: "Info"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .menubar: "menubar.rectangle"
        case .module(let module): module.symbol
        case .notifications: "bell.badge"
        case .about: "info.circle"
        }
    }
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
    @State private var page: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Section {
                    row(.general)
                    row(.menubar)
                }
                Section("Moduli") {
                    ForEach(ModuleID.available) { row(.module($0)) }
                }
                Section {
                    row(.notifications)
                    row(.about)
                }
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
        case .general: GeneralSettings(settings: settings)
        case .menubar: MenubarSettings(model: model, snapshot: feed.snapshot, settings: settings)
        case .module(let module): ModuleSettings(module: module, model: model, snapshot: feed.snapshot, settings: settings)
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
    @State private var loginEnabled = LoginItem.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

struct MenubarSettings: View {
    var model: AppModel
    var snapshot: Snapshot
    @ObservedObject var settings: Settings

    var body: some View {
        let context = MenubarRenderer.Context(snapshot: snapshot, options: MenubarOptions(settings),
                                              recent: { model.recentValues($0, count: $1) },
                                              weather: model.weather.report, weatherConfigured: settings.weatherLocation != nil)
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Anteprima") {
                MenubarPreview(image: MenubarRenderer.image(for: settings.visibleModules, context: context).image, vertical: true)
            }
            SettingsSection(title: "Aspetto") {
                Picker("Disposizione", selection: $settings.layout) {
                    ForEach(MenubarLayout.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Toggle("Mostra le etichette sopra i valori (CPU, MEM, …)", isOn: $settings.showLabels)
                Toggle("Icone dinamiche: cambiano in base a cosa fa il Mac", isOn: $settings.dynamicIcons)
                if settings.dynamicIcons {
                    Text("Ventola che gira quando le ventole sono attive · fiamma con CPU sotto carico · termometro che sale e avviso di rallentamento termico · frecce di rete e disco accese solo con traffico · batteria con fulmine, spina o foglia (basso consumo) · avviso con pressione di memoria alta.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            SettingsSection(title: "Moduli", footnote: "Trascina per cambiare l'ordine. In modalità separata puoi anche ⌘-trascinare le voci nella barra.") {
                List {
                    ForEach(settings.moduleOrder) { module in
                        HStack(spacing: 10) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Toggle(isOn: Binding(get: { settings.isEnabled(module) }, set: { settings.setEnabled(module, $0) })) {
                                Label(module.name, systemImage: module.symbol).frame(width: 130, alignment: .leading)
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
                                              weather: model.weather.report, weatherConfigured: settings.weatherLocation != nil)
        return MenubarRenderer.image(for: [module], context: context).image
    }

    var body: some View {
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
        case .network:
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
        } else {
            switch location.status {
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
            Image(systemName: "location.fill").foregroundStyle(Palette.color(0))
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
                Text("Monitor di sistema per la barra dei menu. Implementazione indipendente ispirata a iStat Menus.")
                Text("Versione \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "sviluppo")")
                    .foregroundStyle(.secondary)
            }
            SettingsSection(title: "Storico", footnote: "Medie al minuto di tutte le metriche, conservate 8 giorni.") {
                Text(HistoryStore.defaultURL.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting([HistoryStore.defaultURL]) }
                    Button("Cancella storico", role: .destructive) {
                        model.history.clear()
                        cleared = true
                    }
                    if cleared { Text("Storico cancellato").foregroundStyle(.secondary) }
                }
            }
        }
    }
}

/// Install / remove the privileged helper used for fan control.
struct HelperSettings: View {
    @ObservedObject var hardware: HardwareControl

    var body: some View {
        SettingsSection(title: "Helper con privilegi", footnote: "Un piccolo servizio di sistema (LaunchDaemon) scrive la velocità delle ventole nello SMC. Accetta comandi solo da questa copia di MenuStats e rifiuta velocità fuori dai limiti di fabbrica. Dopo l'installazione macOS chiede di consentirlo in Impostazioni di Sistema ▸ Generali ▸ Elementi login.") {
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
