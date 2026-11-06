import AppKit
import Combine
import Foundation
import SQLite3

/// What the Calendar filter of a macOS Focus ("Full immersion") does with the calendars.
enum FocusCalendarRule: Equatable {
    /// Only these calendars.
    case show(Set<String>)
    /// Every calendar but these.
    case hide(Set<String>)

    /// macOS stores the filter as an NSPredicate on the calendar identifiers:
    /// `NOT SELF IN {"A", "B"}` (hide) or `SELF IN {"A"}` (show).
    static func parse(predicate: String) -> FocusCalendarRule? {
        let text = predicate.trimmingCharacters(in: .whitespaces)
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else { return nil }
        let head = text[..<open].uppercased().replacingOccurrences(of: " ", with: "")
        let ids = Set(text[text.index(after: open)..<close].split(separator: ",").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" '"))
        }.filter { !$0.isEmpty })
        switch head {
        case "NOTSELFIN": return .hide(ids)
        case "SELFIN": return ids.isEmpty ? nil : .show(ids)
        default: return nil
        }
    }

    /// The other form macOS keeps: the filter's App Intent with its `calendars` parameter (the ones to show).
    static func parse(encodedAction data: Data) -> FocusCalendarRule? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let parameters = plist["SerializedParameters"] as? [String: Any] else { return nil }
        let entries: [[String: Any]]
        switch parameters["calendars"] {
        case let one as [String: Any]: entries = [one]
        case let many as [[String: Any]]: entries = many
        default: return nil
        }
        let ids = Set(entries.compactMap { $0["identifier"] as? String })
        return ids.isEmpty ? nil : .show(ids)
    }
}

/// A Focus that is on right now, with its Calendar filter if it has one.
struct ActiveFocus: Equatable {
    var modeID: String
    var name: String
    var calendars: FocusCalendarRule?
}

/// Reads the Focus modes the user set up in System Settings ▸ Focus: which one is on (Assertions.json), their names
/// (ModeConfigurations.json) and their app filters (Settings.sqlite). macOS keeps these files private: reading them
/// needs Full Disk Access. Nothing is ever written.
enum SystemFocusStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
    static let calendarFilterIdentifier = "SetCalendarFocusConfiguration"

    enum ReadError: Error { case noPermission }

    /// Modes switched on now, from the assertions macOS keeps (manual, scheduled or automatic).
    static func activeModeIDs(assertions data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stores = root["data"] as? [[String: Any]] else { return [] }
        var ids: [String] = []
        for store in stores {
            for record in store["storeAssertionRecords"] as? [[String: Any]] ?? [] {
                if let details = record["assertionDetails"] as? [String: Any],
                   let mode = details["assertionDetailsModeIdentifier"] as? String, !ids.contains(mode) {
                    ids.append(mode)
                }
            }
        }
        return ids
    }

    /// Mode identifier → the name shown in System Settings.
    static func modeNames(configurations data: Data) -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stores = root["data"] as? [[String: Any]] else { return [:] }
        var names: [String: String] = [:]
        for store in stores {
            for (id, value) in store["modeConfigurations"] as? [String: Any] ?? [:] {
                if let mode = (value as? [String: Any])?["mode"] as? [String: Any], let name = mode["name"] as? String {
                    names[id] = name
                }
            }
        }
        return names
    }

    /// The built-in modes keep an English name in the file; System Settings shows them translated.
    static func displayName(modeID: String, stored: String?) -> String {
        let builtIn = [
            "com.apple.donotdisturb.mode.default": "Non disturbare",
            "com.apple.focus.reduce-interruptions": "Meno interruzioni",
            "com.apple.sleep.sleep-mode": "Riposo",
            "com.apple.donotdisturb.mode.driving": "Alla guida",
            "com.apple.focus.work": "Lavoro",
            "com.apple.focus.personal-time": "Tempo personale",
            "com.apple.donotdisturb.mode.workout": "Allenamento",
            "com.apple.focus.gaming": "Gioco",
            "com.apple.focus.mindfulness": "Mindfulness",
            "com.apple.focus.reading": "Lettura",
        ]
        return builtIn[modeID] ?? stored ?? "Full immersion"
    }

    /// Mode identifier → its Calendar filter, from the Focus settings database.
    static func calendarRules(database url: URL) -> [String: FocusCalendarRule] {
        var db: OpaquePointer?
        let uri = "file:\(url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path)?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return [:]
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        let query = """
            SELECT m.ZIDENTIFIER, s.ZPREDICATEFORMAT, s.ZENCODEDACTION
            FROM ZPERMODESETTINGS s JOIN ZFOCUSMODE m ON m.Z_PK = s.ZMODE
            WHERE s.ZIDENTIFIER = ? AND (s.ZENABLED IS NULL OR s.ZENABLED != 0)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, calendarFilterIdentifier, -1, transient)
        var predicates: [String: FocusCalendarRule] = [:], actions: [String: FocusCalendarRule] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let mode = sqlite3_column_text(statement, 0).map({ String(cString: $0) }) else { continue }
            if let text = sqlite3_column_text(statement, 1).map({ String(cString: $0) }),
               let rule = FocusCalendarRule.parse(predicate: text) {
                predicates[mode] = rule
            }
            if let bytes = sqlite3_column_blob(statement, 2) {
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))
                if let rule = FocusCalendarRule.parse(encodedAction: data) { actions[mode] = rule }
            }
        }
        // The intent's parameter names exactly the calendars the user ticked; the predicate (every other calendar
        // macOS knew when the filter was saved) is the fallback, and misses calendars added later.
        return predicates.merging(actions) { _, action in action }
    }

    /// The Focus on right now (nil: none). With several on, the first that has a Calendar filter.
    static func read() -> Result<ActiveFocus?, ReadError> {
        let assertionsURL = directory.appendingPathComponent("Assertions.json")
        guard let assertions = try? Data(contentsOf: assertionsURL) else { return .failure(.noPermission) }
        let active = activeModeIDs(assertions: assertions)
        guard !active.isEmpty else { return .success(nil) }
        let names = (try? Data(contentsOf: directory.appendingPathComponent("ModeConfigurations.json")))
            .map(modeNames(configurations:)) ?? [:]
        let rules = calendarRules(database: directory.appendingPathComponent("Settings.sqlite"))
        let mode = active.first { rules[$0] != nil } ?? active[0]
        return .success(ActiveFocus(modeID: mode, name: displayName(modeID: mode, stored: names[mode]), calendars: rules[mode]))
    }

    /// The files change when a Focus turns on or off or its filters are edited.
    static func stamp() -> [Date]? {
        let files = ["Assertions.json", "ModeConfigurations.json", "Settings.sqlite", "Settings.sqlite-wal"]
        let dates = files.map {
            (try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent($0).path))?[.modificationDate] as? Date
        }
        return dates.first == nil || dates[0] == nil ? nil : dates.map { $0 ?? .distantPast }
    }
}

/// Follows the macOS Focus: while one with a Calendar filter is on, MenuStats shows the calendars that filter picks.
/// Checks the Focus files every few seconds (a stat of four files; they are read again only when they change).
final class FocusCalendarFilter: ObservableObject {
    enum Status: Equatable {
        /// "Follow Focus" is off in Settings.
        case off
        /// macOS refuses the files: MenuStats needs Full Disk Access.
        case noPermission
        case inactive
        case active(ActiveFocus)
    }

    static let shared = FocusCalendarFilter()

    @Published private(set) var status: Status = .off

    /// The rule in force now, nil when no Focus with a Calendar filter is on.
    var rule: FocusCalendarRule? {
        if case .active(let focus) = status { return focus.calendars }
        return nil
    }

    private var timer: Timer?
    private var lastStamp: [Date]?
    private let queue = DispatchQueue(label: "menustats.focus", qos: .utility)

    func setEnabled(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        lastStamp = nil
        guard enabled else {
            status = .off
            return
        }
        refresh()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Reads the Focus again if its files changed (always when `force`, e.g. after granting Full Disk Access).
    func refresh(force: Bool = false) {
        queue.async { [weak self] in
            guard let self else { return }
            let stamp = SystemFocusStore.stamp()
            if !force, stamp != nil, stamp == self.lastStamp { return }
            self.lastStamp = stamp
            let status: Status = switch SystemFocusStore.read() {
            case .failure: .noPermission
            case .success(nil): .inactive
            case .success(let focus?): .active(focus)
            }
            DispatchQueue.main.async {
                guard self.timer != nil, status != self.status else { return }
                self.status = status
            }
        }
    }

    /// System Settings ▸ Privacy & Security ▸ Full Disk Access.
    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// System Settings ▸ Focus, where the filters are set up.
    static func openFocusSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
