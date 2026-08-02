//
//  StageVCPumpTests.swift
//  Stageable
//
//  Task 16: the pump (D4). A synchronous transition must not strand the queue,
//  and a command from a completion issues exactly one plan — never two at once.
//

import XCTest
@testable import Stageable

private final class PropScreen: UIViewController, Stageable {
    var propViews: [UIView] = []
    var props: [Prop] { propViews.map { Prop($0, from: .bottom) } }
    var entered = 0
    func didEnter() { entered += 1 }
}

@MainActor
final class StageVCPumpTests: XCTestCase {

    private var stage = StageVC()
    private var held: [() -> Void] = []

    override func setUp() {
        super.setUp()
        stage = StageVC()
        stage.view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        held = []
        stage.animate = { [self] _, _, _, animations, completion in
            animations()
            held.append(completion)
        }
    }

    /// Fire everything currently held. Swapped out first: a completion can
    /// start new animators, which must not append into a mid-mutation array.
    private func fireHeld() {
        let pending = held
        held = []
        for completion in pending { completion() }
    }

    private func screen(props count: Int) -> PropScreen {
        let screen = PropScreen()
        screen.view.frame = stage.view.bounds
        screen.propViews = (0..<count).map { i in
            let v = UIView(frame: CGRect(x: 50, y: 100 + i * 120, width: 100, height: 100))
            screen.view.addSubview(v)
            return v
        }
        return screen
    }

    // MARK: - A synchronous transition doesn't strand the queue

    func testQueueDrainsPastASynchronousTransition() {
        // x's entrance is async (one prop), so a and b queue behind it. a→b is
        // then propless→propless: b's ENTIRE transition runs inside the drain's
        // call frame (F6) — the loop must run it to completion, not strand it
        // behind its own swallowed re-entrant drain.
        let x = screen(props: 1), a = screen(props: 0), b = screen(props: 0)
        stage.push(x)
        stage.push(a)
        stage.push(b)
        XCTAssertEqual(a.entered, 0, "queued behind x's in-flight transition")

        // Land every async phase (x's enter; then x's prop parking on a's
        // exit). Everything after that must land without the clock's help.
        while !held.isEmpty { fireHeld() }

        XCTAssertEqual(a.entered, 1, "a ran")
        XCTAssertEqual(b.entered, 1, "b must not strand behind its own synchronous transition")
        XCTAssertTrue(stage.top === b)
    }

    // MARK: - A command from a completion issues exactly one plan

    func testPushFromACompletionRunsOnceAfterTheCurrentPlanLands() {
        let a = screen(props: 0), b = screen(props: 0)
        var order: [String] = []

        stage.push(a) { [self] outcome in
            order.append("a:\(outcome)")
            stage.push(b) { order.append("b:\($0)") }
        }
        order.append("returned")

        XCTAssertEqual(order, ["a:performed", "b:performed", "returned"])
        XCTAssertEqual(b.entered, 1, "exactly once")
        XCTAssertTrue(stage.top === b)
    }

    func testCompletionPushNeverOverlapsAnInFlightPlan() {
        // a and b both animate. If the pump allowed two concurrent plans,
        // b's animators would appear in `held` while a's are still pending.
        let a = screen(props: 1), b = screen(props: 1)
        stage.push(a) { [self] _ in stage.push(b) }

        XCTAssertEqual(held.count, 1, "only a's enter animator may be running")
        fireHeld()    // land a → completion pushes b

        // b's plan: exit phase (a's 1 prop parks) is the only running phase.
        XCTAssertEqual(held.count, 1, "b's exit phase alone — never two plans at once")
        fireHeld()    // land b's exit
        fireHeld()    // land b's enter

        XCTAssertEqual(b.entered, 1)
        XCTAssertTrue(stage.top === b)
    }

    // MARK: - Settle defers to the plan a completion caused

    func testSettleWaitsForThePlanACompletionCaused() {
        final class SettleCounter: StageObserver {
            var settles = 0
            func stageDidSettle() { settles += 1 }
        }
        let counter = SettleCounter()
        stage.addObserver(counter)

        let a = screen(props: 0), b = screen(props: 0)
        stage.push(a) { [self] _ in stage.push(b) }

        XCTAssertEqual(counter.settles, 1, "one settle, after b — not one per plan")
        XCTAssertTrue(stage.top === b)
    }
}
