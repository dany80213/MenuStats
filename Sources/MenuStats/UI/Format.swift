import Foundation

enum Format {
    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    static func storage(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    /// "194G", "1.2T": for the menu bar.
    static func storageCompact(_ value: UInt64) -> String {
        let gigabytes = Double(value) / 1e9
        return gigabytes >= 1000 ? String(format: "%.1fT", gigabytes / 1000) : String(format: "%.0fG", gigabytes)
    }

    /// Decimal units, like Activity Monitor. Compact form ("1.2M") is for the menu bar.
    static func rate(_ bytesPerSecond: Double, compact: Bool = false) -> String {
        let units = compact ? ["B", "K", "M", "G"] : ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(bytesPerSecond, 0)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let number = (unit > 0 && value < 10) ? String(format: "%.1f", value) : String(format: "%.0f", value)
        return compact ? number + units[unit] : number + " " + units[unit]
    }

    /// Per-process CPU as a percentage of one core, like Activity Monitor.
    static func processCPU(_ fractionOfCore: Double) -> String {
        String(format: "%.1f%%", fractionOfCore * 100)
    }

    static func truncated(_ text: String, to length: Int) -> String {
        text.count > length ? String(text.prefix(length - 1)) + "…" : text
    }

    /// Set from Settings; temperatures are always stored in Celsius.
    static var fahrenheit = false

    static func temperatureValue(_ celsius: Double) -> Double {
        fahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    static func temperature(_ celsius: Double, unit: Bool = true) -> String {
        String(format: unit ? (fahrenheit ? "%.0f°F" : "%.0f°C") : "%.0f°", temperatureValue(celsius))
    }

    static func rpm(_ value: Double) -> String {
        String(format: "%.0f rpm", value)
    }

    static func watts(_ value: Double) -> String {
        String(format: value < 10 ? "%.1f W" : "%.0f W", value)
    }

    /// A process's power draw, like the other process columns: "0.8 W", "12 W"; under 0.05 W "<0.1 W".
    static func processPower(_ watts: Double) -> String {
        if watts < 0.05 { return "<0.1 W" }
        return watts < 10 ? String(format: "%.1f W", watts) : String(format: "%.0f W", watts)
    }

    static func duration(minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func uptime() -> String {
        let seconds = Int(Sysctl.secondsSinceBoot())
        let days = seconds / 86_400, hours = seconds % 86_400 / 3600, minutes = seconds % 3600 / 60
        return days > 0 ? "\(days) g \(hours) h \(minutes) min" : "\(hours) h \(minutes) min"
    }
}
