import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var settingsWindow: SettingsWindowController!
    private var panel: DashboardPanelController!
    private var statusBar: StatusBarController!
    private var updateItem: UpdateStatusItem!
    private var appearance: AppearanceController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        appearance = AppearanceController(settings: model.settings, weather: model.weather)
        settingsWindow = SettingsWindowController(model: model) { [weak self] in self?.appearance.apply() }
        panel = DashboardPanelController(model: model) { [weak self] in self?.settingsWindow.show() }
        panel.onShow = { [weak self] in self?.appearance.apply() }
        statusBar = StatusBarController(model: model, panel: panel) { [weak self] in self?.settingsWindow.show() }
        updateItem = UpdateStatusItem(updater: model.updater) { [weak self] in self?.settingsWindow.show() }
        model.start()
        model.updater.start()
        // The calendar asks for access at launch (macOS shows its prompt only the first time).
        if model.settings.calendarEvents || model.settings.calendarAlerts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [model] in model.calendar.requestAccess() }
        }
        if CommandLine.arguments.contains("--install-update") { model.updater.installWhenAvailable() }

        if let flag = CommandLine.arguments.firstIndex(of: "--self-test"), flag + 1 < CommandLine.arguments.count {
            SelfTest.run(statusBar: statusBar, panel: panel, output: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
        }
    }

    // Opening the app again (Finder, Spotlight) shows the settings, since there is no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }
}
