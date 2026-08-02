//
//  StageVCChromeTests.swift
//  Stageable
//
//  Task 13: chrome. Presence by rule, reconciled against destination state,
//  applied only when the answer changed, above the screens on every path.
//

import XCTest
@testable import Stageable

private final class Screen: UIViewController, Stageable {
    var props: [Prop] { [] }
}

@MainActor
final class StageVCChromeTests: XCTestCase {

    private var stage = StageVC()
    private var applied: [Bool] = []

    override func setUp() {
        super.setUp()
        stage = StageVC()
        stage.view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        // Synchronous stub: these tests are about presence, not the clock.
        stage.animate = { _, _, _, animations, completion in
            animations()
            completion()
        }
        applied = []
    }

    /// A chrome that records every `apply`, present by the given rule.
    private func chrome(_ view: UIView, isPresent: @escaping @MainActor (StageVC) -> Bool) -> Chrome {
        Chrome(view, isPresent: isPresent) { [self] present in applied.append(present) }
    }

    // MARK: - Absent chrome is off-stage before the first screen appears (D1)

    func testAbsentChromeIsAppliedBeforeTheFirstScreen() {
        let banner = UIView()
        stage.setChrome([chrome(banner) { _ in false }])
        XCTAssertEqual(applied, [false], "setChrome must reconcile immediately, un-animated")

        applied = []
        stage.push(Screen())
        XCTAssertEqual(applied, [], "presence did not change; the install must not re-apply")
    }

    // MARK: - Present on both sides: never re-applied (D1)

    func testUnchangedChromeIsNotTouchedByATransition() {
        let header = UIView()
        stage.setChrome([chrome(header) { _ in true }])
        XCTAssertEqual(applied, [true])

        applied = []
        stage.push(Screen())
        stage.push(Screen())
        stage.pop()
        XCTAssertEqual(applied, [], "chrome present throughout must never be re-applied")
    }

    // MARK: - Presence follows the destination, riding the derived phase

    func testDepthRuleAppearsAndDisappearsWithTheStack() {
        let backButton = UIView()
        stage.setChrome([chrome(backButton) { $0.depth > 1 }])
        XCTAssertEqual(applied, [false])

        applied = []
        stage.push(Screen())
        XCTAssertEqual(applied, [], "depth 1: still absent")

        stage.push(Screen())
        XCTAssertEqual(applied, [true], "depth 2: rides the enter phase")

        applied = []
        stage.pop()
        XCTAssertEqual(applied, [false], "back to depth 1: rides the exit phase")
    }

    // MARK: - A strike that changes depth reconciles, bare

    func testStrikeReconcilesChrome() {
        let backButton = UIView()
        stage.setChrome([chrome(backButton) { $0.depth > 1 }])
        let a = Screen(), b = Screen(), c = Screen()
        stage.push(a)
        stage.push(b)
        stage.push(c)
        XCTAssertEqual(applied.last, true)

        applied = []
        stage.setRoot(c)                    // c is showing: a strike, no phases
        XCTAssertEqual(applied, [false], "the strike changed depth; chrome must reconcile")
    }

    // MARK: - setChrome restores a departing chrome

    func testDepartingChromeIsRestoredAndLeavesTheStage() {
        let banner = UIView()
        stage.setChrome([chrome(banner) { _ in false }])
        XCTAssertEqual(applied, [false])
        XCTAssertTrue(banner.superview === stage.view)

        applied = []
        stage.setChrome([])
        XCTAssertEqual(applied, [true], "a chrome last applied absent is put back before it leaves (A4)")
        XCTAssertNil(banner.superview)
    }

    // MARK: - Above the screen on every path

    func testChromeStaysAboveTheScreens() throws {
        let header = UIView()
        stage.setChrome([Chrome(header, isPresent: { _ in true }, apply: { _ in })])

        let a = Screen(), b = Screen()
        stage.push(a)
        var subviews = stage.view.subviews
        XCTAssertGreaterThan(try XCTUnwrap(subviews.firstIndex(of: header)),
                             try XCTUnwrap(subviews.firstIndex(of: a.view)))

        stage.push(b)
        subviews = stage.view.subviews
        XCTAssertGreaterThan(try XCTUnwrap(subviews.firstIndex(of: header)),
                             try XCTUnwrap(subviews.firstIndex(of: b.view)))

        stage.pop()
        subviews = stage.view.subviews
        XCTAssertGreaterThan(try XCTUnwrap(subviews.firstIndex(of: header)),
                             try XCTUnwrap(subviews.firstIndex(of: a.view)))
    }

    // MARK: - refreshChrome mid-transition defers to settle

    func testRefreshChromeOutsideATransitionAppliesImmediately() {
        var visible = true
        let banner = UIView()
        stage.setChrome([chrome(banner) { _ in visible }])
        stage.push(Screen())
        XCTAssertEqual(applied, [true])

        applied = []
        visible = false
        stage.refreshChrome()
        XCTAssertEqual(applied, [false])
    }
}
