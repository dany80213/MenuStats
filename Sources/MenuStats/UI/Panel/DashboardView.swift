import SwiftUI

final class DashboardState: ObservableObject {
    @Published var tab: DashboardTab = .cpu
    /// While the panel is closed the content isn't built, so it doesn't re-render (and query history) on every sample.
    @Published var visible = true
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The dropdown panel. Builds its content only while visible.
struct DashboardView: View {
    static let width: CGFloat = 372

    var model: AppModel
    @ObservedObject var state: DashboardState
    var maxContentHeight: CGFloat
    var openSettings: () -> Void
    var quit: () -> Void
    var onLayoutChange: () -> Void = {}

    var body: some View {
        if state.visible {
            DashboardContent(model: model, state: state, maxContentHeight: maxContentHeight,
                             openSettings: openSettings, quit: quit, onLayoutChange: onLayoutChange)
        } else {
            Color.clear.frame(width: Self.width, height: 1)
        }
    }
}

/// Tab bar, shared chart range, the selected tab, and a footer.
struct DashboardContent: View {
    static let width = DashboardView.width

    @ObservedObject var model: AppModel
    @ObservedObject var state: DashboardState
    var maxContentHeight: CGFloat
    var openSettings: () -> Void
    var quit: () -> Void
    /// Called when the content height changes, so the panel can resize.
    var onLayoutChange: () -> Void = {}

    @AppStorage("chart.range") private var rangeRaw = HistoryRange.live.rawValue
    @State private var contentHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            Picker("", selection: $rangeRaw) {
                ForEach(HistoryRange.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: contentHeight > maxContentHeight) {
                content
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .background(GeometryReader { Color.clear.preference(key: ContentHeightKey.self, value: $0.size.height) })
            }
            .frame(height: min(contentHeight, maxContentHeight))
            .onPreferenceChange(ContentHeightKey.self) { height in
                guard abs(height - contentHeight) > 0.5 else { return }
                contentHeight = height
                DispatchQueue.main.async(execute: onLayoutChange)
            }

            Divider()
            footer
        }
        .frame(width: Self.width)
    }

    /// Room for one tab with its label under the icon. With more tabs than fit, the bar switches to icons only and
    /// the selected tab shows its name beside the icon, so labels never shrink or wrap.
    private static let labeledTabWidth: CGFloat = 54

    private var tabBar: some View {
        let tabs = visibleTabs
        let compact = CGFloat(tabs.count) * Self.labeledTabWidth > Self.width - 20
        return HStack(spacing: 2) {
            ForEach(tabs) { tab in
                let selected = state.tab == tab
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { state.tab = tab }
                } label: {
                    Group {
                        if compact {
                            HStack(spacing: 5) {
                                tabIcon(tab, selected: selected)
                                if selected { tabLabel(tab, selected: true, size: 11).fixedSize() }
                            }
                            .padding(.horizontal, selected ? 9 : 0)
                            .frame(height: 30)
                            .frame(maxWidth: selected ? nil : .infinity)
                        } else {
                            VStack(spacing: 3) {
                                tabIcon(tab, selected: selected)
                                tabLabel(tab, selected: selected)
                            }
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.primary.opacity(0.09) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
    }

    private func tabIcon(_ tab: DashboardTab, selected: Bool) -> some View {
        Image(systemName: tab.symbol).font(.system(size: 13, weight: .medium)).frame(height: 16)
            .foregroundStyle(severity(of: tab).color ?? model.settings.customColor(for: tab) ?? (selected ? Color.primary : Color.secondary))
    }

    private func tabLabel(_ tab: DashboardTab, selected: Bool, size: CGFloat = 9.5) -> some View {
        Text(tab.title)
            .font(.system(size: size, weight: selected ? .semibold : .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    /// System tabs always; Weather and Date only while their module is enabled.
    private var visibleTabs: [DashboardTab] { DashboardTab.allCases.filter(isEnabledTab) }

    private func isEnabledTab(_ tab: DashboardTab) -> Bool {
        switch tab {
        case .weather: model.settings.isEnabled(.weather)
        // The calendar's events live in the Date tab: it shows once the calendar is connected, even without the module.
        case .date: model.settings.isEnabled(.date) || (model.settings.calendarEvents && model.calendar.access == .granted)
        case .awake: model.settings.isEnabled(.awake)
        default: true
        }
    }

    /// Worst alert among the modules shown in a tab (sensors covers temperatures and fans).
    private func severity(of tab: DashboardTab) -> Severity {
        let settings = model.settings
        guard settings.severityColors else { return .normal }
        return ModuleID.allCases.filter { $0.tab == tab }.map {
            Severity.of($0, snapshot: model.snapshot, cpuBusy: settings.cpuBusyThreshold,
                        temperatureHot: settings.temperatureHotThreshold, source: settings.sensorSource)
        }.max() ?? .normal
    }

    @ViewBuilder private var content: some View {
        let _ = Palette.tab = state.tab
        switch state.tab {
        case .cpu: CPUTab(model: model)
        case .memory: MemoryTab(model: model)
        case .disk: DiskTab(model: model)
        case .network: NetworkTab(model: model)
        case .sensors: SensorsTab(model: model)
        case .battery: BatteryTab(model: model)
        case .weather: WeatherTab(weather: model.weather, openSettings: openSettings)
        case .date: DateTab(weather: model.weather, calendarService: model.calendar)
        case .awake: AwakeTab(model: model)
        case .map: MapTab(proximity: model.proximity, openSettings: openSettings)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { SystemActions.openActivityMonitor() } label: { Label("Monitoraggio Attività", systemImage: "chart.bar.xaxis") }
            Spacer()
            Menu {
                Picker("Aspetto", selection: Binding(get: { model.settings.appearanceMode }, set: { model.settings.appearanceMode = $0 })) {
                    ForEach(AppearanceMode.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.inline)
                Picker("Sfondo", selection: Binding(get: { model.settings.panelBackground }, set: { model.settings.panelBackground = $0 })) {
                    ForEach(PanelBackground.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: model.settings.appearanceMode.symbol)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Aspetto e sfondo della tendina")
            Button(action: openSettings) { Image(systemName: "gearshape") }.help("Impostazioni…")
            Button(action: quit) { Image(systemName: "power") }.help("Esci da MenuStats")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
