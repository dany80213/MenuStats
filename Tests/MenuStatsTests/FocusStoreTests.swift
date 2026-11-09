import SQLite3
import XCTest
@testable import MenuStats

/// The Focus files as macOS 27 writes them (same JSON keys and Core Data tables as ~/Library/DoNotDisturb/DB),
/// built in a temporary folder: the whole chain from "which Focus is on" to "which calendars it shows".
final class FocusStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("focus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try modes([("com.apple.donotdisturb.mode.default", "Do Not Disturb"), ("com.apple.focus.work", "Work"),
                   ("A1B2-CUSTOM", "Studio")])
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    private func write(_ json: String, _ name: String) throws {
        try Data(json.utf8).write(to: folder.appendingPathComponent(name))
    }

    private func modes(_ list: [(String, String)]) throws {
        let entries = list.map { #""\#($0.0)":{"mode":{"name":"\#($0.1)","modeIdentifier":"\#($0.0)"}}"# }
        try write(#"{"data":[{"modeConfigurations":{\#(entries.joined(separator: ","))}}],"header":{"version":3}}"#, "ModeConfigurations.json")
    }

    private func active(_ modes: [String]) throws {
        let records = modes.map { #"{"assertionDetails":{"assertionDetailsModeIdentifier":"\#($0)","assertionDetailsReason":"user-action"}}"# }
        try write(#"{"data":[{"storeAssertionRecords":[\#(records.joined(separator: ","))]}],"header":{"version":8}}"#, "Assertions.json")
    }

    /// One row per filter: (mode, predicate, calendars the intent names, enabled).
    private func filters(_ rows: [(String, String?, [String]?, Bool)]) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(folder.appendingPathComponent("Settings.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        sqlite3_exec(db, """
            CREATE TABLE ZFOCUSMODE (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZIDENTIFIER VARCHAR);
            CREATE TABLE ZPERMODESETTINGS (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZENABLED INTEGER, ZMODE INTEGER,
              ZAPPLICATION INTEGER, ZIDENTIFIER VARCHAR, ZPREDICATEFORMAT VARCHAR, ZTARGETCONTENTIDENTIFIERPREFIX VARCHAR,
              ZENCODEDACTION BLOB, ZENCODEDACTION1 BLOB, ZENCODEDREVERSEACTION BLOB);
            """, nil, nil, nil)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, row) in rows.enumerated() {
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO ZFOCUSMODE (Z_PK, ZIDENTIFIER) VALUES ((SELECT COALESCE(MAX(Z_PK),0)+1 FROM ZFOCUSMODE), ?)", -1, &statement, nil)
            sqlite3_bind_text(statement, 1, row.0, -1, transient)
            if try modePK(db, row.0) == nil { sqlite3_step(statement) }
            sqlite3_finalize(statement)
            let mode = try XCTUnwrap(modePK(db, row.0))
            sqlite3_prepare_v2(db, "INSERT INTO ZPERMODESETTINGS (Z_PK, ZENABLED, ZMODE, ZIDENTIFIER, ZPREDICATEFORMAT, ZENCODEDACTION) VALUES (?, ?, ?, 'SetCalendarFocusConfiguration', ?, ?)", -1, &statement, nil)
            sqlite3_bind_int(statement, 1, Int32(index + 1))
            sqlite3_bind_int(statement, 2, row.3 ? 1 : 0)
            sqlite3_bind_int(statement, 3, mode)
            if let predicate = row.1 { sqlite3_bind_text(statement, 4, predicate, -1, transient) } else { sqlite3_bind_null(statement, 4) }
            if let calendars = row.2 {
                let value: Any = calendars.count == 1 ? ["identifier": calendars[0]] : calendars.map { ["identifier": $0] }
                let data = try PropertyListSerialization.data(fromPropertyList: ["SerializedParameters": ["calendars": value]], format: .binary, options: 0)
                _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 5, $0.baseAddress, Int32(data.count), transient) }
            } else { sqlite3_bind_null(statement, 5) }
            XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
            sqlite3_finalize(statement)
        }
    }

    private func modePK(_ db: OpaquePointer?, _ identifier: String) throws -> Int32? {
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT Z_PK FROM ZFOCUSMODE WHERE ZIDENTIFIER = ?", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, identifier, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : nil
    }

    private func read() throws -> ActiveFocus? { try SystemFocusStore.read(in: folder).get() }

    func testWorkFocusShowsOnlyItsCalendars() throws {
        try filters([("com.apple.focus.work", #"NOT SELF IN {"casa", "famiglia"}"#, ["lavoro", "scuola"], true),
                     ("com.apple.donotdisturb.mode.default", #"NOT SELF IN {"lavoro"}"#, ["personale"], true)])
        try active(["com.apple.focus.work"])
        let focus = try XCTUnwrap(read())
        XCTAssertEqual(focus.name, "Lavoro")
        XCTAssertEqual(focus.calendars, .show(["lavoro", "scuola"]))
        let visible = CalendarService.visibleCalendarIDs(all: ["lavoro", "scuola", "casa", "famiglia", "personale"],
                                                         hidden: [], focus: focus.calendars)
        XCTAssertEqual(visible, ["lavoro", "scuola"])
    }

    func testSwitchingFocusSwitchesCalendars() throws {
        try filters([("com.apple.focus.work", nil, ["lavoro"], true),
                     ("com.apple.donotdisturb.mode.default", nil, ["personale"], true)])
        try active(["com.apple.donotdisturb.mode.default"])
        XCTAssertEqual(try read()?.calendars, .show(["personale"]))
        try active(["com.apple.focus.work"])
        XCTAssertEqual(try read()?.calendars, .show(["lavoro"]))
        try active([])
        XCTAssertNil(try read())
    }

    func testPredicateWhenTheIntentHasNoCalendars() throws {
        try filters([("A1B2-CUSTOM", #"NOT SELF IN {"casa"}"#, nil, true)])
        try active(["A1B2-CUSTOM"])
        let focus = try XCTUnwrap(read())
        XCTAssertEqual(focus.name, "Studio")
        XCTAssertEqual(focus.calendars, .hide(["casa"]))
    }

    func testFocusWithoutCalendarFilterOrDisabledFilter() throws {
        try filters([("com.apple.focus.work", nil, ["lavoro"], false)])
        try active(["com.apple.focus.work"])
        let focus = try XCTUnwrap(read())
        XCTAssertNil(focus.calendars)
    }

    func testTwoFocusesOnPicksTheOneWithAFilter() throws {
        try filters([("com.apple.focus.work", nil, ["lavoro"], true)])
        try active(["com.apple.donotdisturb.mode.default", "com.apple.focus.work"])
        XCTAssertEqual(try read()?.modeID, "com.apple.focus.work")
    }

    func testUnreadableFolderIsNoPermission() {
        let missing = folder.appendingPathComponent("non-esiste")
        if case .failure(.noPermission) = SystemFocusStore.read(in: missing) {} else { XCTFail("atteso noPermission") }
    }
}
