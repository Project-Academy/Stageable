//
//  StageVCPhaseTests.swift
//  Stageable
//
//  Task 14: F6. A phase ends when its LAST animator completes — never before,
//  never on a timer — and a phase with no animators takes no time.
//

import XCTest
@testable import Stageable

private final class PropScreen: UIViewController, Stageable {
    var propViews: [UIView] = []
    var props: [Prop] { propViews.map { Prop($0, from: .bottom) } }
    var entered = 0
    var exited: [Exit] = []
    func didEnter() { entered += 1 }
    func didExit(_ exit: Exit) { exited.append(exit) }
}

/// Records the stage-level hooks.
private final class RecordingStage: StageVC {
    var log: [String] = []
    override func stageDidEnd(_ phase: Phase) { log.append("didEnd(\(phase))") }
    override func stageDidSettle() { log.append("settle") }
}

@MainActor
final class StageVCPhaseTests: XCTestCase {

    private var stage = RecordingStage()
    /// Completions the stub animator is holding — the test is the clock.
    private var held: [() -> Void] = []

    override func setUp() {
        super.setUp()
        stage = RecordingStage()
        stage.view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        held = []
        stage.animate = { [self] _, _, _, animations, completion in
            animations()
            held.append(completion)
        }
    }

    private func screen(withViews count: Int) -> PropScreen {
        let screen = PropScreen()
        screen.view.frame = stage.view.bounds
        screen.propViews = (0..<count).map { i in
            let v = UIView(frame: CGRect(x: 50, y: 100 + i * 120, width: 100, height: 100))
            screen.view.addSubview(v)
            return v
        }
        return screen
    }

    // MARK: - The phase ends when the LAST animator completes

    func testEnterPhaseEndsOnlyWhenitsLastAnimatorCompletes() {
        let a = screen(withViews: 2)
        stage.push(a)

        XCTAssertEqual(held.count, 2, "two props: two animators")
        XCTAssertEqual(a.entered, 0)
        XCTAssertTrue(stage.log.isEmpty)

        held[0]()
        XCTAssertEqual(a.entered, 0, "one animator still running: the phase has not ended")

        held[1]()
        XCTAssertEqual(a.entered, 1)
        XCTAssertEqual(stage.log, ["didEnd(enter)", "settle"])
    }

    func testExitPhaseEndsOnlyWhenItsLastAnimatorCompletes() {
        let a = screen(withViews: 2), b = screen(withViews: 0)
        stage.push(a)
        held.removeAll { $0(); return true }        // land a's entrance
        stage.log = []

        stage.push(b)
        XCTAssertEqual(held.count, 2, "a's two props park on the exit phase")
        XCTAssertEqual(a.exited, [], "willExit fired, but didExit waits for the phase")

        held[0]()
        XCTAssertEqual(a.exited, [])
        XCTAssertTrue(a.view.superview === stage.view, "the view leaves only when the phase ends")

        held[1]()
        XCTAssertEqual(a.exited, [.covered])
        XCTAssertNil(a.view.superview)
        // b has no props: its enter phase took no time and everything landed.
        XCTAssertEqual(stage.log, ["didEnd(exit)", "didEnd(enter)", "settle"])
        XCTAssertEqual(b.entered, 1)
    }

    // MARK: - A phase with no animators takes no time

    func testPhaseWithNoAnimatorsCompletesInTheSameRunloopTurn() {
        stage.animate = { _, _, _, _, _ in
            XCTFail("a phase with no animators must never touch the animator")
        }
        let a = screen(withViews: 0)
        stage.push(a)

        XCTAssertEqual(a.entered, 1, "the whole transition must land synchronously")
        XCTAssertEqual(stage.log, ["didEnd(enter)", "settle"])
    }

    // MARK: - Chrome rides the phase's animator

    func testChromeChangeCountsAsAPhaseAnimator() {
        var presences: [Bool] = []
        let banner = UIView()
        stage.setChrome([Chrome(banner, isPresent: { $0.depth > 1 },
                                apply: { presences.append($0) })])
        XCTAssertEqual(presences, [false])

        let a = screen(withViews: 0), b = screen(withViews: 0)
        stage.push(a)                               // depth 1: nothing changes, no animators
        XCTAssertEqual(a.entered, 1)

        stage.push(b)                               // depth 2: chrome rides the enter phase
        XCTAssertEqual(held.count, 1, "the chrome change is the phase's only animator")
        XCTAssertEqual(presences, [false, true], "apply runs inside the animator's block")
        XCTAssertEqual(b.entered, 0, "the phase is still open until its animator completes")

        held[0]()
        XCTAssertEqual(b.entered, 1)
    }
}
