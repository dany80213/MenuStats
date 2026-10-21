import XCTest
@testable import MenuStats

final class MenubarFitTests: XCTestCase {
    /// 4 modules of 100 pt with labels, 90 pt without; 10 pt between them.
    private func width(_ step: MenubarFit.Step) -> CGFloat {
        CGFloat(step.moduleCount) * (step.labels ? 100 : 90) + CGFloat(max(step.moduleCount - 1, 0)) * 10
    }

    func testLadderGoesLabelsFirstThenOneModuleAtATime() {
        let ladder = MenubarFit.ladder(count: 4, labelsConfigured: true, width: width)
        XCTAssertEqual(ladder.map(\.step), [
            .init(moduleCount: 4, labels: true), .init(moduleCount: 4, labels: false), .init(moduleCount: 3, labels: false),
            .init(moduleCount: 2, labels: false), .init(moduleCount: 1, labels: false),
        ])
        XCTAssertEqual(ladder.map(\.width), [430, 390, 290, 190, 90])
    }

    func testLabelsStayWhenDroppingThemSavesNoRoom() {
        // Without labels this style is wider: the labels stay and modules go one at a time.
        let ladder = MenubarFit.ladder(count: 3, labelsConfigured: true) { step in
            CGFloat(step.moduleCount) * (step.labels ? 100 : 110)
        }
        XCTAssertEqual(ladder.map(\.step), [.init(moduleCount: 3, labels: true), .init(moduleCount: 2, labels: true),
                                            .init(moduleCount: 1, labels: true)])
        XCTAssertTrue(zip(ladder, ladder.dropFirst()).allSatisfy { $0.width > $1.width }, "every step is narrower")
    }

    func testNoLabelsConfigured() {
        let ladder = MenubarFit.ladder(count: 2, labelsConfigured: false, width: width)
        XCTAssertEqual(ladder.map(\.step), [.init(moduleCount: 2, labels: false), .init(moduleCount: 1, labels: false)])
    }

    func testChoosesTheWidestStepThatFits() {
        let ladder = MenubarFit.ladder(count: 4, labelsConfigured: true, width: width)
        XCTAssertEqual(MenubarFit.choose(ladder, room: 500, current: 0), 0)
        XCTAssertEqual(MenubarFit.choose(ladder, room: 400, current: 0), 1)
        XCTAssertEqual(MenubarFit.choose(ladder, room: 300, current: 0), 2, "jumps straight to the step that fits")
        XCTAssertEqual(MenubarFit.choose(ladder, room: 50, current: 0), 4, "never less than one module")
    }

    func testGrowsBackOnlyWithMargin() {
        let ladder = MenubarFit.ladder(count: 4, labelsConfigured: true, width: width)
        XCTAssertEqual(MenubarFit.choose(ladder, room: 395, current: 2), 2, "390 needs 16 pt more to come back")
        XCTAssertEqual(MenubarFit.choose(ladder, room: 410, current: 2), 1)
        XCTAssertEqual(MenubarFit.choose(ladder, room: 1000, current: 3), 0)
    }

    func testRoomIsMeasuredOnlyNextToANotch() {
        XCTAssertEqual(MenubarFit.room(rightEdge: 1360, notchRightEdge: 860), 490)
        XCTAssertNil(MenubarFit.room(rightEdge: 1360, notchRightEdge: nil))
    }
}

final class AIActivityTests: XCTestCase {
    func testDescribe() {
        XCTAssertEqual(AwakeController.describe(["Claude Code"]), "Claude Code al lavoro")
        XCTAssertEqual(AwakeController.describe(["Claude Code", "Codex"]), "Claude Code e Codex al lavoro")
        XCTAssertEqual(AwakeController.describe(["Claude Code", "Claude Code"]), "2 sessioni di Claude Code al lavoro")
    }

    func testRecentTranscriptMeansWorking() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ai-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("progetto")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let fresh = project.appendingPathComponent("sessione.jsonl"), old = project.appendingPathComponent("vecchia.jsonl")
        try Data("{}".utf8).write(to: fresh)
        try Data("{}".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: old.path)
        let monitor = AIActivityMonitor(sources: [.init(tool: "Prova", root: root, depth: 2, extensions: ["jsonl"])], hookDirectory: nil)
        XCTAssertEqual(monitor.activeTranscripts(), ["Prova"], "only the file written in the last 45 s counts")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-120)], ofItemAtPath: fresh.path)
        XCTAssertEqual(monitor.activeTranscripts(), [])
    }

    func testWorkingCountsHookFiles() throws {
        let hooks = FileManager.default.temporaryDirectory.appendingPathComponent("hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: hooks) }
        try Data().write(to: hooks.appendingPathComponent("strumento"))
        let monitor = AIActivityMonitor(sources: [], hookDirectory: hooks)
        XCTAssertEqual(monitor.sample(hookStaleMinutes: 30).sessions, ["IA"])
    }
}

final class AIAgentMatchTests: XCTestCase {
    func testOnlyAgentExecutablesCount() {
        // Claude Code inside the Claude app, and the CLI: yes.
        XCTAssertEqual(AIActivityMonitor.agentTool(forExecutable: "/Users/x/Library/Application Support/Claude/claude-code/2.1/abc/claude.app/Contents/MacOS/claude"), "Claude Code")
        XCTAssertEqual(AIActivityMonitor.agentTool(forExecutable: "/opt/homebrew/bin/claude"), "Claude Code")
        XCTAssertEqual(AIActivityMonitor.agentTool(forExecutable: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"), "Codex")
        // The Claude desktop app itself (its window helpers always use CPU): no.
        XCTAssertNil(AIActivityMonitor.agentTool(forExecutable: "/Applications/Claude.app/Contents/MacOS/Claude"))
        XCTAssertNil(AIActivityMonitor.agentTool(forExecutable: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper"))
        XCTAssertNil(AIActivityMonitor.agentTool(forExecutable: "/Applications/Fake.app/Contents/MacOS/claude"), "a GUI app named claude")
        XCTAssertNil(AIActivityMonitor.agentTool(forExecutable: "/usr/bin/node"))
    }

    func testDisplaySleepFromPmset() {
        let output = " Sleep On Power Button 1\n sleep                1 (sleep prevented by powerd)\n displaysleep         5\n disksleep            10\n"
        XCTAssertEqual(AwakeController.parseDisplaySleep(output), 5)
        XCTAssertNil(AwakeController.parseDisplaySleep("nothing here"))
    }

    func testAnItemAboveADisplayWithAHiddenMenuBarIsNotOutOfRoom() {
        // Measured with an HP 24o left of a U27B3A whose bar was hidden by an app in full screen.
        let screens = [CGRect(x: -1920, y: 360, width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 2560, height: 1440)]
        XCTAssertTrue(MenubarFit.isOverHiddenMenuBar(CGRect(x: 1967, y: 1472, width: 488, height: 30), screens: screens))
        XCTAssertFalse(MenubarFit.isOverHiddenMenuBar(CGRect(x: -593, y: 1410, width: 488, height: 30), screens: screens),
                       "in the HP's menu bar")
        XCTAssertFalse(MenubarFit.isOverHiddenMenuBar(CGRect(x: 2076, y: 1410, width: 484, height: 30), screens: screens),
                       "in the U27B3A's menu bar")
        XCTAssertFalse(MenubarFit.isOverHiddenMenuBar(CGRect(x: -2600, y: 1410, width: 488, height: 30), screens: screens),
                       "pushed off every display")
    }
}
