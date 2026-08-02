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
       - overlay: App-readable overlay tag; not read by the engine. Defaults to `true`.
     */
    public init(_ view: UIView, from direction: Direction, delay: TimeInterval = 0, overlay: Bool = true) {
        self.view = view
        self.direction = direction
        self.transform = nil
        self.delay = delay
        self.overlay = overlay
    }

    /**
     Creates a prop with a custom off-screen transform (e.g. scale-to-zero).
     - Parameters:
       - view: The view to animate.
       - transform: The transform applied when the view is off-screen.
       - delay: Stagger delay in seconds. Defaults to `0`.
       - overlay: App-readable overlay tag; not read by the engine. Defaults to `true`.
     */
    public init(_ view: UIView, transform: CGAffineTransform, delay: TimeInterval = 0, overlay: Bool = true) {
        self.view = view
        self.direction = nil
        self.transform = transform
        self.delay = delay
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
        let screen = view.superview?.bounds ?? UIScreen.main.bounds
        let frame = view.frame

        let toLeft = -(frame.maxX)
        let toRight = screen.width - frame.minX
        let toTop = -(frame.maxY)
        let toBottom = screen.height - frame.minY

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
}
