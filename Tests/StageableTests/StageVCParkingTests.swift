//
//  StageVCParkingTests.swift
//  Stageable
//
//  Task 12: the ledger. Every parked view comes back to the recorded value —
//  not to whatever the container observes at restore time (A4).
//

import XCTest
@testable import Stageable

/// A screen whose props can be swapped mid-test.
private final class PropScreen: UIViewController, Stageable {
    var propViews: [UIView] = []
    var props: [Prop] { propViews.map { Prop($0, from: .bottom) } }
}

@MainActor
final class StageVCParkingTests: XCTestCase {

    private var stage = StageVC()

    override func setUp() {
        super.setUp()
        stage = StageVC()
        stage.view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        // Synchronous stub: these tests are about the ledger, not the clock.
        stage.animate = { _, _, _, animations, completion in
            animations()
            completion()
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

    // MARK: - Restored to the recorded value

    func testEnteredScreensViewsAreAtTheirRecordedTransforms() {
        let a = screen(withViews: 2)
        // A non-identity resting transform: A4 says put it BACK, not to .identity.
        let resting = CGAffineTransform(scaleX: 0.5, y: 0.5)
        a.propViews[1].transform = resting

        stage.push(a)

        XCTAssertEqual(a.propViews[0].transform, .identity)
        XCTAssertEqual(a.propViews[1].transform, resting)
    }

    // MARK: - A covered screen's views wait off-screen; the pop restores them

    func testCoveredScreenParksAndPopRestores() {
        let a = screen(withViews: 1), b = screen(withViews: 0)
        stage.push(a)
        XCTAssertEqual(a.propViews[0].transform, .identity)

        stage.push(b)
        XCTAssertNotEqual(a.propViews[0].transform, .identity,
                          "a covered screen's props must be parked off-screen")

        stage.pop()
        XCTAssertEqual(a.propViews[0].transform, .identity,
                       "the pop back must restore the recorded value")
        XCTAssertTrue(a.view.superview === stage.view)
    }

    // MARK: - Props changed between park and restore: the LEDGER decides

    func testRestoreUsesTheLedgerNotTheCurrentProps() {
        let a = screen(withViews: 2), b = screen(withViews: 0)
        let parked = a.propViews

        stage.push(a)
        stage.push(b)                       // parks BOTH of a's views

        // The screen now claims a different prop set. A4: restore what was
        // recorded at park, not what props returns today.
        let latecomer = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        let latecomerTransform = CGAffineTransform(rotationAngle: 0.5)
        latecomer.transform = latecomerTransform
        a.view.addSubview(latecomer)
        a.propViews = [latecomer]

        stage.pop()

        XCTAssertEqual(parked[0].transform, .identity, "originally parked view 0 must be restored")
        XCTAssertEqual(parked[1].transform, .identity, "originally parked view 1 must be restored")
        // The latecomer was never parked by the covering; after the pop's own
        // enter cycle (park + immediate restore), it is back where it started.
        XCTAssertEqual(latecomer.transform, latecomerTransform)
    }

    // MARK: - Screens leaving for good get everything put back

    func testRemovedScreenIsRestoredOnRelease() {
        let a = screen(withViews: 1), b = screen(withViews: 1)
        stage.push(a)
        stage.push(b)
        stage.pop()                         // b leaves for good

        XCTAssertEqual(b.propViews[0].transform, .identity,
                       "a removed screen's views must not stay parked")
        XCTAssertNil(b.parent)
    }

    func testStruckScreensAreRestoredOnRelease() {
        let a = screen(withViews: 1), b = screen(withViews: 1), c = screen(withViews: 0)
        stage.push(a)
        stage.push(b)
        stage.push(c)
        stage.setRoot(c)                    // strikes a and b

        XCTAssertEqual(a.propViews[0].transform, .identity)
        XCTAssertEqual(b.propViews[0].transform, .identity)
        XCTAssertNil(a.parent)
        XCTAssertNil(b.parent)
    }
}
