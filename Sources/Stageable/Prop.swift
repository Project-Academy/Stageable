//
//  Prop.swift
//  Stageable
//
//  Created by Sarfraz Basha on 18/03/2026.
//

import UIKit

/**
 A declarative description of how a single view enters and exits the stage.

 Each ``Stageable`` view controller returns an array of `Prop`s. The ``StageVC``
 animation engine uses them to choreograph entrance and exit transitions — sliding
 views on from a screen edge or applying a custom off-screen transform.

 ```swift
 var props: [Prop] {
     [
         Prop(titleLabel, from: .top),
         Prop(cardView,   from: .bottom, delay: 0.05),
         Prop(avatar,     transform: .init(scaleX: 0, y: 0), delay: 0.1)
     ]
 }
 ```
 */
@MainActor
public struct Prop {
    /// The view that will be animated on/off screen.
    public let view: UIView
    /// The edge the view slides from. Mutually exclusive with ``transform``.
    public let direction: Direction?
    /// A custom off-screen transform. Mutually exclusive with ``direction``.
    public let transform: CGAffineTransform?
    /// Seconds to wait before this prop's animation starts, creating a stagger effect.
    public let delay: TimeInterval
    /// Seconds to wait before this prop leaves, where that differs from its wait coming in: two props whose paths
    /// cross come in one after the other and leave in the opposite order. Nil leaves after ``delay``.
    public let exitDelay: TimeInterval?
    /// App-readable metadata: whether this prop belongs to the screen's
    /// toggleable overlay chrome (e.g. a focus mode that hides everything but
    /// the content). **The engine never reads this** — it exists so a screen's
    /// own chrome logic can filter its one `props` declaration instead of
    /// keeping a parallel list that can drift from it.
    public let overlay: Bool

    /// A screen edge (or corner) that a ``Prop`` slides in from and out toward.
    public enum Direction {
        case top, bottom, left, right
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /**
     Creates a prop that slides in from a screen edge.
     - Parameters:
       - view: The view to animate.
       - direction: The edge the view enters from.
       - delay: Stagger delay in seconds. Defaults to `0`.
       - exitDelay: The delay on the way out, where it differs. Defaults to `delay`.
       - overlay: App-readable overlay tag; not read by the engine. Defaults to `true`.
     */
    public init(_ view: UIView, from direction: Direction, delay: TimeInterval = 0, exitDelay: TimeInterval? = nil, overlay: Bool = true) {
        self.view = view
        self.direction = direction
        self.transform = nil
        self.delay = delay
        self.exitDelay = exitDelay
        self.overlay = overlay
    }

    /**
     Creates a prop with a custom off-screen transform (e.g. scale-to-zero).
     - Parameters:
       - view: The view to animate.
       - transform: The transform applied when the view is off-screen.
       - delay: Stagger delay in seconds. Defaults to `0`.
       - exitDelay: The delay on the way out, where it differs. Defaults to `delay`.
       - overlay: App-readable overlay tag; not read by the engine. Defaults to `true`.
     */
    public init(_ view: UIView, transform: CGAffineTransform, delay: TimeInterval = 0, exitDelay: TimeInterval? = nil, overlay: Bool = true) {
        self.view = view
        self.direction = nil
        self.transform = transform
        self.delay = delay
        self.exitDelay = exitDelay
        self.overlay = overlay
    }

    /**
     Returns the transform that places this view off-screen,
     calculated from the view's current frame and the screen bounds.
     */
    public func offScreenTransform() -> CGAffineTransform {
        if let transform { return transform }
        guard let direction else { return .identity }

        // Measured entirely in the SUPERVIEW's space.
        //
        // `view.frame` is already expressed in those coordinates, so the bounds
        // it is compared against must be too. Two earlier versions got this
        // wrong in opposite directions:
        //
        //  · Comparing `frame` against `UIScreen.main.bounds` mixed two spaces,
        //    so a prop inside an inset container stopped short of the edge and
        //    hung there in view — and any window that isn't full-screen (Split
        //    View, Stage Manager) made every prop travel the whole display.
        //  · Resolving the frame with `convert(_:to:)` fixed that but folded
        //    ANCESTOR transforms into the measurement. A prop whose ancestor was
        //    already displaced — an inner stage's scene while the outer stage
        //    animates its host away — then measured as already off-screen and
        //    was given a translation of zero, so it did not animate at all.
        //
        // Staying in one space is immune to both. A prop travels off its own
        // superview, which for a scene filling the stage is the stage.
        // Superview → window → screen. `UIScreen.main.bounds` is the LAST
        // resort because it is orientation-naive: on an iPad in landscape it
        // still reads portrait (1032 wide, not 1194), which is narrower than
        // the laid-out frame of any trailing-edge view. That made `.right`
        // negative for a top-right button — it flew in from the LEFT.
        let container = view.superview?.bounds ?? view.window?.bounds ?? UIScreen.main.bounds
        let frame = view.frame

        // In a window, the edges it travels to are the WINDOW's, set in the
        // superview's space: a stage that sits inside its host (Books' is
        // under the status bar) has a top edge that is still in sight, and a
        // prop sent only that far waits there half out. The window's edges are
        // found by layout alone (each ancestor's centre, size and scroll
        // offset), so a displaced ancestor's transform stays out of it.
        let edges = Self.windowEdges(inSuperviewOf: view)
            ?? CGRect(origin: .zero, size: container.size)

        // A prop travels toward its named edge or it does not travel: a
        // measurement that came out backwards means the container is wrong,
        // and standing still is always better than sliding the wrong way.
        let toLeft = min(0, edges.minX - frame.maxX)
        let toRight = max(0, edges.maxX - frame.minX)
        let toTop = min(0, edges.minY - frame.maxY)
        let toBottom = max(0, edges.maxY - frame.minY)

        switch direction {
        case .top:         return CGAffineTransform(translationX: 0, y: toTop)
        case .bottom:      return CGAffineTransform(translationX: 0, y: toBottom)
        case .left:        return CGAffineTransform(translationX: toLeft, y: 0)
        case .right:       return CGAffineTransform(translationX: toRight, y: 0)
        case .topLeft:     return CGAffineTransform(translationX: toLeft, y: toTop)
        case .topRight:    return CGAffineTransform(translationX: toRight, y: toTop)
        case .bottomLeft:  return CGAffineTransform(translationX: toLeft, y: toBottom)
        case .bottomRight: return CGAffineTransform(translationX: toRight, y: toBottom)
        }
    }

    /// The window's bounds in the space `view.frame` is measured in, by layout
    /// alone; nil for a view that is not in a window.
    private static func windowEdges(inSuperviewOf view: UIView) -> CGRect? {
        guard let window = view.window, let parent = view.superview else { return nil }
        // Where the superview's own space starts in the window.
        var start = CGPoint(x: -parent.bounds.origin.x, y: -parent.bounds.origin.y)
        var node: UIView? = parent
        while let current = node, current !== window {
            start.x += current.center.x - current.bounds.width * current.layer.anchorPoint.x
            start.y += current.center.y - current.bounds.height * current.layer.anchorPoint.y
            if let above = current.superview, above !== window {
                start.x -= above.bounds.origin.x
                start.y -= above.bounds.origin.y
            }
            node = current.superview
        }
        return CGRect(x: -start.x, y: -start.y, width: window.bounds.width, height: window.bounds.height)
    }
}
