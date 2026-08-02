//
//  NavigatorQueueTests.swift
//  Stageable
//
//  Task 7: the queue. Ordering is FIFO, a no-op never stalls what's behind it,
//  and a command enqueued mid-flight runs exactly once, on the next drain.
//

import XCTest
@testable import Stageable

private final class Screen: UIViewController, Stageable {
    var props: [Prop] { [] }
}

@MainActor
final class NavigatorQueueTests: XCTestCase {

    private var nav = Navigator()
    private let a = Screen(), b = Screen(), c = Screen()

    override func setUp() {
        super.setUp()
        nav = Navigator()
    }

    private func install(_ screen: Screen) {
        _ = nav.enqueue(.push(screen, completion: nil))
        _ = nav.next()
    }

    // MARK: - Ordering

    func testQueuedCommandsConsumeInFIFOOrder() throws {
        _ = nav.enqueue(.push(a, completion: nil))
        _ = nav.enqueue(.push(b, completion: nil))
        _ = nav.enqueue(.push(c, completion: nil))

        for expected in [a, b, c] {
            let (plan, settled) = nav.next()
            XCTAssertTrue(settled.isEmpty)
            guard case .transition(_, let incoming, _, _, _)? = plan
            else { return XCTFail("expected a transition") }
            XCTAssertTrue(incoming === expected)
        }
        XCTAssertEqual(nav.depth, 3)
    }

    // MARK: - A no-op doesn't stall the queue

    func testNoopIsConsumedAndTheNextCommandStillPlans() throws {
        install(a)
        _ = nav.enqueue(.pop(completion: nil))      // at root: noop
        _ = nav.enqueue(.push(b, completion: nil))  // must still run

        let (plan, settled) = nav.next()
        XCTAssertEqual(settled.count, 1)
        guard case (.pop, .noop) = settled[0] else { return XCTFail("expected (.pop, .noop)") }
        guard case .transition(_, let incoming, _, _, _)? = plan
        else { return XCTFail("the push behind the noop never planned") }
        XCTAssertTrue(incoming === b)
    }

    func testConsecutiveNoopsAllSettleInOneCall() {
        install(a)
        _ = nav.enqueue(.pop(completion: nil))
        _ = nav.enqueue(.popToRoot(completion: nil))
        _ = nav.enqueue(.replaceTop(a, completion: nil))   // already showing: noop

        let (plan, settled) = nav.next()
        XCTAssertNil(plan)
        XCTAssertEqual(settled.count, 3)
        XCTAssertTrue(settled.allSatisfy { $0.1 == .noop })
    }

    // MARK: - Enqueued mid-flight: exactly once, on the next drain

    func testCommandEnqueuedMidFlightRunsExactlyOnceAfterLanding() throws {
        // A plan is issued for `a` and is notionally in flight — the container
        // has not called next() again yet.
        _ = nav.enqueue(.push(a, completion: nil))
        _ = nav.next()

        // "didEnter() pushes b": enqueue lands in the queue, nothing consumes it
        // until the container drains after settle.
        _ = nav.enqueue(.push(b, completion: nil))
        XCTAssertTrue(nav.top === a, "the stack must not move before the drain")

        let (plan, settled) = nav.next()
        XCTAssertTrue(settled.isEmpty)
        guard case .transition(let outgoing, let incoming, _, _, _)? = plan
        else { return XCTFail("expected b's transition") }
        XCTAssertTrue(outgoing === a)
        XCTAssertTrue(incoming === b)

        // Exactly once: the queue is now empty.
        let (again, againSettled) = nav.next()
        XCTAssertNil(again)
        XCTAssertTrue(againSettled.isEmpty)
    }
}
