import SwiftUI
import XCTest
@testable import MenuStats

final class AppearanceColorTests: XCTestCase {
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    func testAlbaETramontoUsesWeatherTimes() {
        let today = WeatherReport.Day(date: date(0), code: 0, minimum: 5, maximum: 15, precipitationChance: nil,
                                      sunrise: date(7, 10), sunset: date(17, 5))
        XCTAssertTrue(AppearanceController.isNight(at: date(6, 59), today: today))
        XCTAssertFalse(AppearanceController.isNight(at: date(12), today: today))
        XCTAssertTrue(AppearanceController.isNight(at: date(17, 6), today: today))
        // Without Weather: from 20:00 to 7:00.
        XCTAssertFalse(AppearanceController.isNight(at: date(19, 59), today: nil))
        XCTAssertTrue(AppearanceController.isNight(at: date(20), today: nil))
        XCTAssertTrue(AppearanceController.scheduleDescription(today: today, now: date(12)).contains("17:05"))
    }

    func testEveryRoleOfATabCanBeChanged() {
        let settings = Settings.shared
        let saved = settings.panelColors
        defer { settings.panelColors = saved }
        // CPU: both "Utente" and "Sistema" (the old picker only reached the first one).
        settings.setPanelColor("#112233", tab: .cpu, role: 0)
        settings.setPanelColor("#445566", tab: .cpu, role: 1)
        XCTAssertEqual(settings.panelColorHex(.cpu, 0), "#112233")
        XCTAssertEqual(settings.panelColorHex(.cpu, 1), "#445566")
        XCTAssertTrue(settings.isCustomPanelColor(.cpu, 1))
        settings.setPanelColor(nil, tab: .cpu, role: 1)
        XCTAssertFalse(settings.isCustomPanelColor(.cpu, 1))
        // Every role a tab lists is one its views draw with (no duplicates).
        for tab in DashboardTab.allCases {
            let roles = tab.colorRoles.map(\.index)
            XCTAssertEqual(Set(roles).count, roles.count, "\(tab)")
            XCTAssertTrue(roles.contains(tab.primaryColorIndex), "\(tab)")
        }
    }

    func testNetworkAndDiskShareColorsWithMenuBarGraphs() {
        let settings = Settings.shared
        let saved = settings.graphSeriesColors
        defer { settings.graphSeriesColors = saved }
        settings.setPanelColor("#ABCDEF", tab: .network, role: 1)
        XCTAssertEqual(settings.graphSeriesColors[.upload], "#ABCDEF")
        settings.graphSeriesColors[.read] = "#010203"
        XCTAssertEqual(settings.panelColorHex(.disk, 0), "#010203")
        settings.setPanelColor(nil, tab: .network, role: 1)
        XCTAssertEqual(settings.graphSeriesColors[.upload], GraphSeries.defaultColors[.upload])
    }

    func testProcessPowerFormat() {
        XCTAssertEqual(Format.processPower(0.01), "<0.1 W")
        XCTAssertEqual(Format.processPower(0.84), "0.8 W")
        XCTAssertEqual(Format.processPower(12.4), "12 W")
    }

    func testEnergyGroupsByApp() {
        let processes = [
            ProcessUsage(pid: 1, name: "Claude Helper", path: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper",
                         cpu: 0, memory: 0, diskReadRate: 0, diskWriteRate: 0, power: 0.5),
            ProcessUsage(pid: 2, name: "Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude",
                         cpu: 0, memory: 0, diskReadRate: 0, diskWriteRate: 0, power: 0.25),
        ]
        let groups = ProcessGrouping.groups(processes, byApp: true)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].power, 0.75, accuracy: 0.001)
    }

    func testPresetSetsEveryColorAndCanBeRestored() {
        let settings = Settings.shared
        let saved = (settings.panelColors, settings.graphSeriesColors, settings.moduleColors, settings.colorPreset, settings.colorPresetFingerprint)
        defer {
            settings.panelColors = saved.0; settings.graphSeriesColors = saved.1; settings.moduleColors = saved.2
            settings.colorPreset = saved.3; settings.colorPresetFingerprint = saved.4
        }
        let ocean = ColorPreset.all.first { $0.id == "ocean" }!
        settings.apply(ocean)
        for tab in DashboardTab.allCases {
            for role in tab.colorRoles.map(\.index) {
                XCTAssertEqual(settings.panelColorHex(tab, role), ocean.hex(tab: tab, role: role), "\(tab) \(role)")
            }
        }
        XCTAssertEqual(settings.graphSeriesColors[.download], ocean.palette[0])
        XCTAssertNotEqual(settings.graphSeriesColors[.read], settings.graphSeriesColors[.download])
        XCTAssertEqual(settings.moduleColors[.cpu], ocean.palette[0])
        XCTAssertEqual(settings.currentPreset?.preset.id, "ocean")
        XCTAssertEqual(settings.currentPreset?.edited, false)
        // Editing one color afterwards shows as "modificato".
        settings.setPanelColor("#000000", tab: .cpu, role: 1)
        XCTAssertEqual(settings.currentPreset?.edited, true)
        // The MenuStats preset puts back the built-in colors.
        settings.apply(ColorPreset.all[0])
        XCTAssertTrue(settings.panelColors.isEmpty)
        XCTAssertEqual(settings.graphSeriesColors, GraphSeries.defaultColors)
        XCTAssertEqual(settings.moduleColors, Settings.defaultColors)
        XCTAssertTrue(ColorPreset.all.allSatisfy { $0.palette.count == 5 && $0.palette.allSatisfy { NSColor(hex: $0) != nil } })
    }

    func testLidStateIsReadable() {
        // On a MacBook with the lid open, or a desktop: never reported closed.
        XCTAssertFalse(AwakeController.lidIsClosed())
    }
}
