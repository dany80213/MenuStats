import AppKit

/// A row of a "top processes" list: one process, or all processes of one app combined.
struct ProcessGroup: Identifiable {
    var id: String
    var name: String
    /// Path used for the icon (the .app bundle when known).
    var iconPath: String
    var count: Int
    var cpu: Double
    var memory: UInt64
    var diskRead: Double
    var diskWrite: Double
    var networkDown: Double = 0
    var networkUp: Double = 0
    /// Watts.
    var power: Double = 0
}

enum ProcessGrouping {
    /// The outermost .app bundle in an executable path, e.g. ".../Claude.app/Contents/Frameworks/Claude Helper.app/..." → Claude.app.
    static func appBundle(of path: String) -> (name: String, path: String)? {
        guard let range = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil)
        else { return nil }
        let bundlePath = String(path[..<range.upperBound]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let full = "/" + bundlePath
        return ((full as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: ""), full)
    }

    static func groups(_ processes: [ProcessUsage], byApp: Bool) -> [ProcessGroup] {
        var groups: [String: ProcessGroup] = [:]
        for process in processes {
            let app = byApp ? appBundle(of: process.path) : nil
            let key = app?.path ?? "pid:\(process.pid)"
            var group = groups[key] ?? ProcessGroup(
                id: key, name: app?.name ?? process.name, iconPath: app?.path ?? process.path,
                count: 0, cpu: 0, memory: 0, diskRead: 0, diskWrite: 0
            )
            group.count += 1
            group.cpu += process.cpu
            group.memory += process.memory
            group.diskRead += process.diskReadRate
            group.diskWrite += process.diskWriteRate
            group.power += process.power
            groups[key] = group
        }
        return Array(groups.values)
    }

    /// Network usage comes from nettop (name + pid); paths are resolved through the process list.
    static func networkGroups(_ usage: [ProcessNetworkUsage], processes: [ProcessUsage], byApp: Bool) -> [ProcessGroup] {
        let paths = Dictionary(processes.map { ($0.pid, $0.path) }, uniquingKeysWith: { first, _ in first })
        var groups: [String: ProcessGroup] = [:]
        for entry in usage {
            let path = paths[entry.pid] ?? ""
            let app = byApp ? appBundle(of: path) : nil
            let key = app?.path ?? "pid:\(entry.pid)"
            var group = groups[key] ?? ProcessGroup(
                id: key, name: app?.name ?? entry.name, iconPath: app?.path ?? path,
                count: 0, cpu: 0, memory: 0, diskRead: 0, diskWrite: 0
            )
            group.count += 1
            group.networkDown += entry.downloadRate
            group.networkUp += entry.uploadRate
            groups[key] = group
        }
        return Array(groups.values)
    }
}

/// Cached app/executable icons for process rows.
enum IconCache {
    private static var cache: [String: NSImage] = [:]
    private static let generic: NSImage = {
        let image = NSWorkspace.shared.icon(for: .unixExecutable)
        image.size = NSSize(width: 16, height: 16)
        return image
    }()

    static func icon(for path: String) -> NSImage {
        guard !path.isEmpty else { return generic }
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 16, height: 16)
        cache[path] = image
        return image
    }
}
