//
//  PropOffsetTests.swift
//  StageableTests
//
//  Pins the direction semantics of `Prop.offScreenTransform()`. Written
//  2026-08-03 chasing a report that a top-right close button entered from
//  the LEFT: the math needs to be provably right before the search moves
//  anywhere else, and "I read it and it looks fine" is not evidence.
//

import XCTest
import UIKit
@testable import Stageable

@MainActor
final class PropOffsetTests: XCTestCase {

    /// iPad landscape, a 44pt button pinned 20pt from the trailing edge —
    /// the settings close button's exact geometry.
    private func closeButtonSetup() -> (host: UIView, button: UIView) {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 1194, height: 834))
        let button = UIView(frame: CGRect(x: 1194 - 20 - 44, y: 20, width: 44, height: 44))
        host.addSubview(button)
        return (host, button)
    }

    /// `.right` must push the view OFF the trailing edge — a positive x —
    /// so the entrance travels leftward into place.
    func testRightIsPositiveForATrailingEdgeView() {
        let (host, button) = closeButtonSetup()
        _ = host   // retain: a released superview silently changes the answer
        let t = Prop(button, from: .right).offScreenTransform()
        XCTAssertGreaterThan(t.tx, 0, "`.right` translated the view LEFT")
        XCTAssertEqual(t.ty, 0, accuracy: 0.001)
        // Its leading edge lands exactly on the host's trailing edge.
        XCTAssertEqual(button.frame.minX + t.tx, 1194, accuracy: 0.001)
    }

    /// The mirror case, so a sign flip can't pass both tests.
    func testLeftIsNegativeForATrailingEdgeView() {
        let (host, button) = closeButtonSetup()
        _ = host
        let t = Prop(button, from: .left).offScreenTransform()
        XCTAssertLessThan(t.tx, 0)
        // Its trailing edge lands exactly on the host's leading edge.
        XCTAssertEqual(button.frame.maxX + t.tx, 0, accuracy: 0.001)
    }

    /// A view measured before Auto Layout has positioned it. The travel is
    /// wrong in magnitude but must not invert: a zero frame is the one
    /// state that could plausibly produce a leftward `.right`.
    func testRightStaysPositiveWhenTheFrameIsStillZero() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 1194, height: 834))
        let button = UIView(frame: .zero)
        host.addSubview(button)
        let t = Prop(button, from: .right).offScreenTransform()
        XCTAssertGreaterThan(t.tx, 0)
    }

    /// A container narrower than the view's own x — Split View, Stage
    /// Manager, or the orientation-naive `UIScreen.main.bounds` fallback.
    /// The measurement is meaningless here, but it must never come out
    /// backwards: standing still beats sliding the wrong way.
    func testRightNeverInvertsWhenTheHostIsNarrowerThanTheViewsOrigin() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 834))
        let button = UIView(frame: CGRect(x: 1130, y: 20, width: 44, height: 44))
        host.addSubview(button)
        let t = Prop(button, from: .right).offScreenTransform()
        XCTAssertGreaterThanOrEqual(t.tx, 0, "`.right` must never translate LEFT")
    }

    /// The orphan case that produced the original report's symptom: with no
    /// superview the old code fell back to a PORTRAIT screen width, which is
    /// narrower than a landscape trailing-edge frame, and inverted.
    func testRightNeverInvertsWithNoSuperview() {
        let button = UIView(frame: CGRect(x: 1130, y: 20, width: 44, height: 44))
        let t = Prop(button, from: .right).offScreenTransform()
        XCTAssertGreaterThanOrEqual(t.tx, 0)
    }

    /// The vertical mirror of the same guard.
    func testBottomNeverInvertsWhenTheHostIsShorter() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 1194, height: 300))
        let card = UIView(frame: CGRect(x: 0, y: 700, width: 400, height: 200))
        host.addSubview(card)
        let t = Prop(card, from: .bottom).offScreenTransform()
        XCTAssertGreaterThanOrEqual(t.ty, 0)
    }
}
