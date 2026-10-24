//
//  StageVCRehearsalTests.swift
//  Stageable
//
//  A screen new to the stage is laid out while the exit plays, hidden beneath everything, so the
//  seam has nothing left to build; it shows at the seam, and a covered screen coming back is not
//  laid out early (its props are parked).
//

import XCTest
@testable import Stageable

private final class LayoutScreen: UIViewController, Stageable {
    var propViews: [UIView] = []
    var props: [Prop] { propViews.map { Prop($0, from: .bottom) } }
    var layouts: [CGSize] = []
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layouts.append(view.bounds.size)
    }
}

@MainActor
final class StageVCRehearsalTests: XCTestCase {

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

    private func screen() -> LayoutScreen {
        let screen = LayoutScreen()
        let prop = UIView(frame: CGRect(x: 50, y: 100, width: 100, height: 100))
        screen.view.addSubview(prop)
        screen.propViews = [prop]
        return screen
    }

    private func landAll() {
        while !held.isEmpty {
            let running = held; held = []
            for completion in running { completion() }
        }
    }

    /// Long enough for the rehearsal, which waits for the exit's last prop to start.
    private func nextTurn() {
        let turned = expectation(description: "rehearsal's turn")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { turned.fulfill() }
        wait(for: [turned], timeout: 1)
    }

    func testANewScreenIsLaidOutHiddenWhileTheExitPlays() {
        let a = screen(), b = screen()
        stage.push(a)
        landAll()

        stage.push(b)                                   // a's exit is running: held, not landed
        nextTurn()
        XCTAssertTrue(b.view.superview === stage.view, "b waits on the stage during the exit")
        XCTAssertTrue(b.view.isHidden, "unseen until its seam")
        XCTAssertEqual(b.view.bounds.size, stage.view.bounds.size)
        XCTAssertEqual(b.layouts.last, stage.view.bounds.size, "laid out at the stage's size")

        landAll()
        XCTAssertFalse(b.view.isHidden, "shown at the seam")
        XCTAssertTrue(stage.view.subviews.last === b.view || stage.view.subviews.contains(b.view))
        XCTAssertNil(a.view.superview, "a left at its exit")
    }

    func testACoveredScreenComingBackIsNotLaidOutEarly() {
        let a = screen(), b = screen()
        stage.push(a)
        landAll()
        stage.push(b)
        landAll()
        a.layouts = []

        stage.pop()                                     // b's exit is running
        nextTurn()
        XCTAssertNil(a.view.superview, "a covered screen waits off the stage: its props are parked")
        XCTAssertTrue(a.layouts.isEmpty)
        landAll()
        XCTAssertFalse(a.view.isHidden)
        XCTAssertTrue(a.view.superview === stage.view)
    }

    func testAScreenWithNoExitToWaitOnEntersAsBefore() {
        let a = LayoutScreen()                          // propless: phases take no time
        let b = LayoutScreen()
        stage.push(a)
        stage.push(b)
        nextTurn()
        XCTAssertTrue(b.view.superview === stage.view)
        XCTAssertFalse(b.view.isHidden, "the seam came first; the late rehearsal does nothing")
    }
}
