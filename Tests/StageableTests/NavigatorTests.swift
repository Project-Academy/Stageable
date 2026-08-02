//
//  NavigatorTests.swift
//  Stageable
//
//  Task 6: each command produces the plan the A7 table claims.
//

import XCTest
@testable import Stageable

/// The minimal conformer — the navigator never looks past identity.
private final class Screen: UIViewController, Stageable {
    var props: [Prop] { [] }
}

@MainActor
final class NavigatorTests: XCTestCase {

    private var nav = Navigator()
    private let a = Screen(), b = Screen(), c = Screen()

    override func setUp() {
        super.setUp()
        nav = Navigator()
    }

    /// Enqueue and immediately consume, asserting no commands settled en route.
    private func plan(for command: Command) -> Plan? {
        let voided = nav.enqueue(command)
        XCTAssertTrue(voided.isEmpty, "enqueue voided \(voided.count) commands unexpectedly")
        let (plan, settled) = nav.next()
        XCTAssertTrue(settled.isEmpty, "\(settled.count) commands settled unexpectedly")
        return plan
    }

    // MARK: - Push

    func testFirstPushHasNoOutgoing() throws {
        let plan = try XCTUnwrap(plan(for: .push(a, completion: nil)))
        guard case .transition(let outgoing, let incoming, let exit, let alsoLeaving, _) = plan
        else { return XCTFail("expected a transition") }
        XCTAssertNil(outgoing)
        XCTAssertTrue(incoming === a)
        XCTAssertEqual(exit, .removed)
        XCTAssertTrue(alsoLeaving.isEmpty)
        XCTAssertTrue(nav.top === a)
        XCTAssertEqual(nav.depth, 1)
    }

    func testPushCoversTheTop() throws {
        _ = plan(for: .push(a, completion: nil))
        let plan = try XCTUnwrap(plan(for: .push(b, completion: nil)))
        guard case .transition(let outgoing, let incoming, let exit, let alsoLeaving, _) = plan
        else { return XCTFail("expected a transition") }
        XCTAssertTrue(outgoing === a)
        XCTAssertTrue(incoming === b)
        XCTAssertEqual(exit, .covered)
        XCTAssertTrue(alsoLeaving.isEmpty)
        XCTAssertEqual(nav.depth, 2)
    }

    // MARK: - Pop

    func testPopRemovesTheTop() throws {
        _ = plan(for: .push(a, completion: nil))
        _ = plan(for: .push(b, completion: nil))
        let plan = try XCTUnwrap(plan(for: .pop(completion: nil)))
        guard case .transition(let outgoing, let incoming, let exit, let alsoLeaving, _) = plan
        else { return XCTFail("expected a transition") }
        XCTAssertTrue(outgoing === b)
        XCTAssertTrue(incoming === a)
        XCTAssertEqual(exit, .removed)
        XCTAssertTrue(alsoLeaving.isEmpty)
        XCTAssertTrue(nav.top === a)
    }

    func testPopAtRootIsANoop() {
        _ = plan(for: .push(a, completion: nil))
        _ = nav.enqueue(.pop(completion: nil))
        let (plan, settled) = nav.next()
        XCTAssertNil(plan)
        XCTAssertEqual(settled.count, 1)
        guard case (.pop, .noop) = settled[0] else { return XCTFail("expected (.pop, .noop)") }
        XCTAssertTrue(nav.top === a)
    }

    // MARK: - replaceTop

    func testReplaceTopSwapsWithoutGrowing() throws {
        _ = plan(for: .push(a, completion: nil))
        _ = plan(for: .push(b, completion: nil))
        let plan = try XCTUnwrap(plan(for: .replaceTop(c, completion: nil)))
        guard case .transition(let outgoing, let incoming, let exit, let alsoLeaving, _) = plan
        else { return XCTFail("expected a transition") }
        XCTAssertTrue(outgoing === b)
        XCTAssertTrue(incoming === c)
        XCTAssertEqual(exit, .removed)
        XCTAssertTrue(alsoLeaving.isEmpty)
        XCTAssertEqual(nav.depth, 2)
        XCTAssertTrue(nav.top === c)
        XCTAssertFalse(nav.contains(b))
    }

    func testReplaceTopOnEmptyInstalls() throws {
        let plan = try XCTUnwrap(plan(for: .replaceTop(a, completion: nil)))
        guard case .transition(let outgoing, let incoming, _, _, _) = plan
        else { return XCTFail("expected a transition") }
        XCTAssertNil(outgoing)
        XCTAssertTrue(incoming === a)
        XCTAssertEqual(nav.depth, 1)
    }

    // MARK: - popToRoot

    func testPopToRootNamesEveryLeaver() throws {
        _ = plan(for: .push(a, completion: nil))
        _ = plan(for: .push(b, completion: nil))
        _ = plan(for: .push(c, completion: nil))
        let plan = try XCTUnwrap(plan(for: .popToRoot(completion: nil)))
        guard case .transition(let outgoing, let incoming, let exit, let alsoLeaving, _) = plan
        else { return XCTFail("expected a transition") }
        XCTAssertTrue(outgoing === c)
        XCTAssertTrue(incoming === a)
        XCTAssertEqual(exit, .removed)
        XCTAssertEqual(alsoLeaving.count, 1)
        XCTAssertTrue(alsoLeaving[0] === b)
        XCTAssertEqual(nav.depth, 1)
    }

    func testPopToRootAtRootIsANoop() {
        _ = plan(for: .push(a, completion: nil))
        _ = nav.enqueue(.popToRoot(completion: nil))
        let (plan, settled) = nav.next()
        XCTAssertNil(plan)
        XCTAssertEqual(settled.count, 1)
        guard case (.popToRoot, .noop) = settled[0] else { return XCTFail("expected (.popToRoot, .noop)") }
    }

    // MARK: - setRoot

    func testSetRootReplacesTheStack() throws {
        _ = plan(for: .push(a, completion: nil))
        _ = plan(for: .push(b, completion: nil))
        let plan = try XCTUnwrap(plan(for: .setRoot(c, completion: nil)))
        guard case .transition(let outgoing, let incoming, let exit, let alsoLeaving, _) = plan
        else { return XCTFail("expected a transition") }
        XCTAssertTrue(outgoing === b)
        XCTAssertTrue(incoming === c)
        XCTAssertEqual(exit, .removed)
        XCTAssertEqual(alsoLeaving.count, 1)
        XCTAssertTrue(alsoLeaving[0] === a)
        XCTAssertEqual(nav.depth, 1)
        XCTAssertTrue(nav.top === c)
    }

    func testSetRootOnEmptyInstalls() throws {
        let plan = try XCTUnwrap(plan(for: .setRoot(a, completion: nil)))
        guard case .transition(let outgoing, let incoming, _, let alsoLeaving, _) = plan
        else { return XCTFail("expected a transition") }
        XCTAssertNil(outgoing)
        XCTAssertTrue(incoming === a)
        XCTAssertTrue(alsoLeaving.isEmpty)
    }

    func testSetRootToTheShowingScreenStrikesTheRest() throws {
        _ = plan(for: .push(a, completion: nil))
        _ = plan(for: .push(b, completion: nil))
        _ = plan(for: .push(c, completion: nil))
        let plan = try XCTUnwrap(plan(for: .setRoot(c, completion: nil)))
        guard case .strike(let screens, _) = plan else { return XCTFail("expected a strike") }
        XCTAssertEqual(screens.count, 2)
        XCTAssertTrue(screens.contains { $0 === a })
        XCTAssertTrue(screens.contains { $0 === b })
        XCTAssertEqual(nav.depth, 1)
        XCTAssertTrue(nav.top === c)
    }

    func testSetRootToTheOnlyScreenIsANoop() {
        _ = plan(for: .push(a, completion: nil))
        _ = nav.enqueue(.setRoot(a, completion: nil))
        let (plan, settled) = nav.next()
        XCTAssertNil(plan)
        XCTAssertEqual(settled.count, 1)
        guard case (.setRoot, .noop) = settled[0] else { return XCTFail("expected (.setRoot, .noop)") }
    }
}
