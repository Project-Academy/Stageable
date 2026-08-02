//
//  NavigatorDiscardTests.swift
//  Stageable
//
//  Task 8: the discard paths. Uniqueness, supersession, and the promise that
//  every command settles exactly once with the outcome that names its fate.
//

import XCTest
@testable import Stageable

private final class Screen: UIViewController, Stageable {
    var props: [Prop] { [] }
}

@MainActor
final class NavigatorDiscardTests: XCTestCase {

    private var nav = Navigator()
    private let a = Screen(), b = Screen(), c = Screen()

    override func setUp() {
        super.setUp()
        nav = Navigator()
    }

    private func install(_ screens: Screen...) {
        for screen in screens {
            _ = nav.enqueue(.push(screen, completion: nil))
            _ = nav.next()
        }
    }

    // MARK: - Duplicate push

    func testPushingAStackedScreenIsDiscarded() {
        install(a, b)
        _ = nav.enqueue(.push(a, completion: nil))
        let (plan, settled) = nav.next()
        XCTAssertNil(plan)
        XCTAssertEqual(settled.count, 1)
        guard case (.push, .discarded) = settled[0] else { return XCTFail("expected (.push, .discarded)") }
        XCTAssertEqual(nav.depth, 2)
    }

    // MARK: - Onto the visible screen

    func testReplaceTopWithTheVisibleScreenIsANoop() {
        install(a, b)
        _ = nav.enqueue(.replaceTop(b, completion: nil))
        let (plan, settled) = nav.next()
        XCTAssertNil(plan)
        guard case (.replaceTop, .noop)? = settled.first else { return XCTFail("expected (.replaceTop, .noop)") }
    }

    func testReplaceTopWithACoveredScreenIsDiscarded() {
        install(a, b)
        _ = nav.enqueue(.replaceTop(a, completion: nil))   // a is mid-stack: would duplicate
        let (plan, settled) = nav.next()
        XCTAssertNil(plan)
        guard case (.replaceTop, .discarded)? = settled.first
        else { return XCTFail("expected (.replaceTop, .discarded)") }
        XCTAssertTrue(nav.top === b)
    }

    // MARK: - setRoot to a screen already in the stack

    func testSetRootToAMidStackScreenTransitionsWithoutDuplicating() throws {
        install(a, b, c)
        _ = nav.enqueue(.setRoot(b, completion: nil))
        let (plan, settled) = nav.next()
        XCTAssertTrue(settled.isEmpty)
        guard case .transition(let outgoing, let incoming, let exit, let alsoLeaving, _)? = plan
        else { return XCTFail("expected a transition") }
        XCTAssertTrue(outgoing === c)
        XCTAssertTrue(incoming === b)
        XCTAssertEqual(exit, .removed)
        XCTAssertEqual(alsoLeaving.count, 1)
        XCTAssertTrue(alsoLeaving[0] === a)
        XCTAssertEqual(nav.depth, 1)
        XCTAssertTrue(nav.top === b)
    }

    // MARK: - Two queued setRoots: the newest wins

    func testNewestSetRootWins() throws {
        install(a)
        _ = nav.enqueue(.setRoot(b, completion: nil))
        let voided = nav.enqueue(.setRoot(c, completion: nil))

        XCTAssertEqual(voided.count, 1)
        guard case (.setRoot(let screen, _), .discarded) = voided[0], screen === b
        else { return XCTFail("expected b's setRoot voided at enqueue") }

        let (plan, settled) = nav.next()
        XCTAssertTrue(settled.isEmpty)
        guard case .transition(_, let incoming, _, _, _)? = plan
        else { return XCTFail("expected c's transition") }
        XCTAssertTrue(incoming === c)
        XCTAssertTrue(nav.top === c)
    }

    func testSetRootVoidsEverythingQueuedBeforeIt() {
        install(a)
        _ = nav.enqueue(.push(b, completion: nil))
        _ = nav.enqueue(.pop(completion: nil))
        let voided = nav.enqueue(.setRoot(c, completion: nil))

        XCTAssertEqual(voided.count, 2)
        XCTAssertTrue(voided.allSatisfy { $0.1 == .discarded })
        guard case .push = voided[0].0, case .pop = voided[1].0
        else { return XCTFail("voided commands out of order") }
    }

    func testCommandsEnqueuedAfterASetRootSurvive() throws {
        install(a)
        _ = nav.enqueue(.setRoot(b, completion: nil))
        let voided = nav.enqueue(.push(c, completion: nil))
        XCTAssertTrue(voided.isEmpty, "a command after the setRoot must not be voided")

        _ = nav.next()                                      // b's transition
        let (plan, _) = nav.next()
        guard case .transition(_, let incoming, _, _, _)? = plan
        else { return XCTFail("expected c's transition") }
        XCTAssertTrue(incoming === c)
        XCTAssertEqual(nav.depth, 2)
    }

    // MARK: - Exactly once

    func testEveryCommandSettlesExactlyOnceWithItsOutcome() {
        var outcomes: [String: [Outcome]] = [:]
        func record(_ key: String) -> (Outcome) -> Void {
            { outcomes[key, default: []].append($0) }
        }

        install(a)
        _ = nav.enqueue(.push(a, completion: record("dupPush")))       // discarded: already stacked
        _ = nav.enqueue(.pop(completion: record("rootPop")))           // noop: at root
        _ = nav.enqueue(.push(b, completion: record("push-b")))        // performs
        let voidedEarly = nav.enqueue(.setRoot(c, completion: record("setRoot-c")))
        XCTAssertEqual(voidedEarly.count, 3, "setRoot voids everything queued before it")

        // The container's contract: fire everything enqueue voided, then drain.
        for (command, outcome) in voidedEarly { command.completion?(outcome) }
        while true {
            let (plan, settled) = nav.next()
            for (command, outcome) in settled { command.completion?(outcome) }
            guard let plan else { break }
            plan.completion?(.performed)
        }

        // Everything before the setRoot was voided at enqueue — including the
        // would-be noop: it never got far enough to be evaluated.
        XCTAssertEqual(outcomes["dupPush"], [.discarded])
        XCTAssertEqual(outcomes["rootPop"], [.discarded])
        XCTAssertEqual(outcomes["push-b"], [.discarded])
        XCTAssertEqual(outcomes["setRoot-c"], [.performed])

        // Now the evaluated paths, with no setRoot sweeping them away.
        outcomes = [:]
        _ = nav.enqueue(.push(c, completion: record("dupPush2")))      // discarded: c is the root
        _ = nav.enqueue(.pop(completion: record("rootPop2")))          // noop: at root
        while true {
            let (plan, settled) = nav.next()
            for (command, outcome) in settled { command.completion?(outcome) }
            guard let plan else { break }
            plan.completion?(.performed)
        }

        XCTAssertEqual(outcomes["dupPush2"], [.discarded])
        XCTAssertEqual(outcomes["rootPop2"], [.noop])
        XCTAssertTrue(outcomes.values.allSatisfy { $0.count == 1 }, "a command settled more than once")
    }
}
