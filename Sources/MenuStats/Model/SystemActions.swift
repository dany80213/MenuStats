import AppKit

/// Actions that change system state. Each one goes through macOS's own authorization prompt.
enum SystemActions {
    /// Low Power Mode via `pmset`, which needs an administrator password (asked by macOS, not by MenuStats).
    static func setLowPowerMode(_ enabled: Bool, completion: @escaping () -> Void) {
        let script = "do shell script \"/usr/bin/pmset -a lowpowermode \(enabled ? 1 : 0)\" with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            if let error { NSLog("MenuStats: pmset failed: \(error)") }
            DispatchQueue.main.async(execute: completion)
        }
    }

    static func openLocationSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
    }

    static func openBatterySettings() {
        open("x-apple.systempreferences:com.apple.Battery-Settings.extension")
    }

    static func openActivityMonitor() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
                                           configuration: .init())
    }

    private static func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}
