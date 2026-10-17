import AppKit
import Combine
import Foundation

/// A slower copy of the latest snapshot (every 5 s), for views that don't need every sample (the settings previews).
final class SlowFeed: ObservableObject {
    @Published fileprivate(set) var snapshot = Snapshot()
    unowned let model: AppModel
    init(model: AppModel) { self.model = model }
}

struct LivePoint {
    var date: Date
    var value: Double
}

/// Shared app state: samples the system on a timer, keeps live buffers and the SQLite history,
/// and publishes each new Snapshot to the menu bar and the dashboard.
final class AppModel: ObservableObject {
    static let liveLength = 150 // 5 minutes at the default 2 s interval

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var networkProcesses: [ProcessNetworkUsage] = []

    let settings: Settings
    let history: HistoryStore
    let hardware = HardwareControl()
    /// Weather from Open-Meteo; idle (no network) unless the Weather module is enabled with a place chosen.
    let weather = WeatherService()
    /// The Mac's city for the Weather module's automatic mode; idle unless that mode is on.
    let location = LocationProvider()
    /// Public IP and VPN for the Network tab; idle unless that tab is open.
    let publicNetwork = PublicNetworkService()
    private(set) lazy var slowFeed = SlowFeed(model: self)
    private var lastSlowUpdate = Date.distantPast
    private let monitor = SystemMonitor()
    private let networkProcessReader = NetworkProcessReader()
    private let alerts = AlertCenter()
    private var live: [Metric: [LivePoint]] = [:]
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: Settings = .shared, history: HistoryStore = HistoryStore()) {
        self.settings = settings
        self.history = history
        networkProcessReader.onUpdate = { [weak self] usage in self?.networkProcesses = usage }
        settings.$refreshInterval
            .removeDuplicates()
            .sink { [weak self] interval in self?.schedule(interval) }
            .store(in: &cancellables)
        // The menu bar's visible modules decide which sources are read every sample.
        Publishers.CombineLatest(settings.$enabledModules, settings.$moduleOrder)
            .sink { [weak self] enabled, order in self?.monitor.demand.menubar = Set(order.filter(enabled.contains)) }
            .store(in: &cancellables)
        Publishers.CombineLatest4(settings.$enabledModules, settings.$weatherLocationMode, settings.$weatherLocation, location.$place)
            .sink { [weak self] enabled, mode, manual, detected in
                let weatherOn = enabled.contains(.weather)
                self?.location.setActive(weatherOn && mode == .automatic)
                self?.weather.configure(enabled: weatherOn, location: mode == .automatic ? (detected ?? manual) : manual)
            }
            .store(in: &cancellables)
        settings.$hiddenSections
            .sink { [weak self] hidden in self?.monitor.demand.hidden = hidden }
            .store(in: &cancellables)

        // Nothing is on screen while the displays sleep or another user is active: stop sampling.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.pause() }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.resume() }
        }
    }

    private var paused = false

    private func pause() {
        paused = true
        timer?.invalidate()
        timer = nil
    }

    private func resume() {
        guard paused else { return }
        paused = false
        tick()
        schedule(settings.refreshInterval)
    }

    func start() {
        tick()
        schedule(settings.refreshInterval)
    }

    private func schedule(_ interval: Double) {
        timer?.invalidate()
        guard interval > 0 else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        // Tolerance lets macOS coalesce this wake-up with others (fewer CPU wake-ups, less energy).
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common) // keeps ticking while menus or the panel are tracking
        self.timer = timer
    }

    func tick() {
        let snapshot = monitor.sample()
        let values = snapshot.historyValues
        history.record(values)
        for (metric, value) in values where value.isFinite {
            var buffer = live[metric] ?? []
            buffer.append(LivePoint(date: snapshot.date, value: value))
            if buffer.count > Self.liveLength { buffer.removeFirst(buffer.count - Self.liveLength) }
            live[metric] = buffer
        }
        alerts.evaluate(snapshot, settings: settings)
        self.snapshot = snapshot
        if snapshot.date.timeIntervalSince(lastSlowUpdate) >= 5 {
            lastSlowUpdate = snapshot.date
            slowFeed.snapshot = snapshot
        }
    }

    func livePoints(_ metric: Metric) -> [LivePoint] { live[metric] ?? [] }

    func warmUpSensors() { monitor.sampleSensorsNow() }

    /// The dashboard tab on screen (nil when closed). Opening or switching tabs samples right away, and again
    /// one second later so per-process rates (which need two samples) appear quickly.
    func setVisibleTab(_ tab: DashboardTab?) {
        guard monitor.demand.tab != tab else { return }
        let opening = monitor.demand.tab == nil && tab != nil
        monitor.demand.tab = tab
        guard let tab else { return }
        if opening { monitor.refreshSoon() }
        tick()
        if [.cpu, .memory, .disk, .network].contains(tab) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard self?.monitor.demand.tab == tab else { return }
                self?.tick()
            }
        }
    }

    /// Recent values for the small graphs drawn in the menu bar.
    func recentValues(_ metric: Metric, count: Int) -> [Double] {
        (live[metric] ?? []).suffix(count).map(\.value)
    }

    // Per-process network sampling is only needed while the network tab is on screen.
    func setNetworkProcessSampling(_ enabled: Bool) {
        if enabled { networkProcessReader.start() } else { networkProcessReader.stop(); networkProcesses = [] }
    }
}
