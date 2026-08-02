//
//  StageVCAppearanceTests.swift
//  Stageable
//
//  Task 15: the A7 table, verbatim. One shared log records every callback in
//  arrival order; each scenario's log must match the table exactly.
//

import XCTest
@testable import Stageable

@MainActor
private final class Sink {
    var log: [String] = []
    func callAsFunction(_ entry: String) { log.append(entry) }
    func drain() -> [String] { defer { log = [] }; return log }
}

private final class LogScreen: UIViewController, Stageable {
    let name: String
    let sink: Sink
    init(_ name: String, _ sink: Sink) {
        self.name = name
        self.sink = sink
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    var props: [Prop] { [] }        // propless: every phase takes no time (F6)
    func willEnter() { sink("\(name).willEnter") }
    func didEnter() { sink("\(name).didEnter") }
    func willExit(_ exit: Exit) { sink("\(name).willExit(\(exit))") }
    func didExit(_ exit: Exit) { sink("\(name).didExit(\(exit))") }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sink("\(name).viewWillAppear")
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sink("\(name).viewDidAppear")
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sink("\(name).viewWillDisappear")
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sink("\(name).viewDidDisappear")
    }
}

private final class LogStage: StageVC {
    var sink: Sink?
    override func stageWillBegin(_ phase: Phase, from: (any Stageable)?, to: (any Stageable)?) {
        sink?("stage.willBegin(\(phase))")
    }
    override func stageDidEnd(_ phase: Phase) { sink?("stage.didEnd(\(phase))") }
    override func stageDidSettle() { sink?("stage.settle") }
}

@MainActor
final class StageVCAppearanceTests: XCTestCase {

    private var stage = LogStage()
    private var sink = Sink()
    private var a: LogScreen!, b: LogScreen!, c: LogScreen!

    override func setUp() {
        super.setUp()
        sink = Sink()
        stage = LogStage()
        stage.sink = sink
        stage.view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        stage.animate = { _, _, _, animations, completion in
            animations()
            completion()
        }
        a = LogScreen("a", sink); b = LogScreen("b", sink); c = LogScreen("c", sink)
        stage.beginAppearanceTransition(true, animated: false)
        stage.endAppearanceTransition()
        _ = sink.drain()
    }

    /// Drive the container's own appearance the way a window would.
    private func appear(_ vc: UIViewController) {
        vc.beginAppearanceTransition(true, animated: false)
        vc.endAppearanceTransition()
    }
    private func disappear(_ vc: UIViewController) {
        vc.beginAppearanceTransition(false, animated: false)
        vc.endAppearanceTransition()
    }

    // MARK: - The table, scenario by scenario

    func testFirstInstall() {
        stage.push(a)
        XCTAssertEqual(sink.log, [
            "a.viewWillAppear",             // seam: begin(true), before willEnter
            "stage.willBegin(enter)",
            "a.willEnter",
            "a.viewDidAppear",              // 8: end, first
            "a.didEnter",
            "stage.didEnd(enter)",
            "stage.settle",
        ])
    }

    func testPush() {
        stage.push(a); _ = sink.drain()
        stage.push(b)
        XCTAssertEqual(sink.log, [
            "stage.willBegin(exit)",        // 1
            "a.willExit(covered)",          // 2
            "a.viewWillDisappear",          // 3
            "a.viewDidDisappear",           // 4
            "a.didExit(covered)",           // 5
            "stage.didEnd(exit)",
            "b.viewWillAppear",             // 6
            "stage.willBegin(enter)",
            "b.willEnter",
            "b.viewDidAppear",              // 8
            "b.didEnter",
            "stage.didEnd(enter)",
            "stage.settle",                 // 9
        ])
    }

    func testPop() {
        stage.push(a); stage.push(b); _ = sink.drain()
        stage.pop()
        XCTAssertEqual(sink.log, [
            "stage.willBegin(exit)",
            "b.willExit(removed)",
            "b.viewWillDisappear",
            "b.viewDidDisappear",
            "b.didExit(removed)",
            "stage.didEnd(exit)",
            "a.viewWillAppear",
            "stage.willBegin(enter)",
            "a.willEnter",
            "a.viewDidAppear",
            "a.didEnter",
            "stage.didEnd(enter)",
            "stage.settle",
        ])
    }

    func testReplaceTop() {
        stage.push(a); stage.push(b); _ = sink.drain()
        stage.replaceTop(with: c)
        XCTAssertEqual(sink.log, [
            "stage.willBegin(exit)",
            "b.willExit(removed)",
            "b.viewWillDisappear",
            "b.viewDidDisappear",
            "b.didExit(removed)",
            "stage.didEnd(exit)",
            "c.viewWillAppear",
            "stage.willBegin(enter)",
            "c.willEnter",
            "c.viewDidAppear",
            "c.didEnter",
            "stage.didEnd(enter)",
            "stage.settle",
        ])
    }

    func testPopToRootGivesAlsoLeaversNoAppearanceCalls() {
        stage.push(a); stage.push(b); stage.push(c); _ = sink.drain()
        stage.popToRoot()
        XCTAssertEqual(sink.log, [
            "stage.willBegin(exit)",
            "c.willExit(removed)",
            "b.willExit(removed)",          // alsoLeaving, at step 2
            "c.viewWillDisappear",
            "c.viewDidDisappear",
            "c.didExit(removed)",
            "b.didExit(removed)",           // step 5 — no appearance calls
            "stage.didEnd(exit)",
            "a.viewWillAppear",
            "stage.willBegin(enter)",
            "a.willEnter",
            "a.viewDidAppear",
            "a.didEnter",
            "stage.didEnd(enter)",
            "stage.settle",
        ])
    }

    func testStrikeHasNoPhasesAndNoAppearanceCalls() {
        stage.push(a); stage.push(b); stage.push(c); _ = sink.drain()
        stage.setRoot(c)
        XCTAssertEqual(sink.log, [
            "a.willExit(removed)",
            "a.didExit(removed)",
            "b.willExit(removed)",
            "b.didExit(removed)",
            "stage.settle",
        ])
    }

    func testNoPlanFiresNothingButTheCompletion() {
        stage.push(a); _ = sink.drain()
        var outcome: Outcome?
        stage.pop { outcome = $0 }
        XCTAssertEqual(outcome, .noop)
        XCTAssertEqual(sink.log, [], "no plan: no callbacks, no settle")
    }

    // MARK: - D5: the container relays its own appearance to the top screen

    func testContainerAppearanceReachesTheTopScreen() {
        stage.push(a); _ = sink.drain()

        disappear(stage)
        XCTAssertEqual(sink.log, ["a.viewWillDisappear", "a.viewDidDisappear"])
        _ = sink.drain()

        appear(stage)
        XCTAssertEqual(sink.log, ["a.viewWillAppear", "a.viewDidAppear"])
    }

    // MARK: - D9: a push into an off-screen container defers appearance

    func testPushWhileContainerOffScreenDeliversAppearanceOnContainerAppear() {
        stage.push(a); _ = sink.drain()
        disappear(stage); _ = sink.drain()

        stage.push(b)
        XCTAssertFalse(sink.log.contains("b.viewWillAppear"),
                       "no appearance while the container is off screen")
        XCTAssertFalse(sink.log.contains("a.viewWillDisappear"))
        _ = sink.drain()

        appear(stage)
        XCTAssertEqual(sink.log, ["b.viewWillAppear", "b.viewDidAppear"],
                       "the container's appearance delivers the top screen's, once")
    }
}
