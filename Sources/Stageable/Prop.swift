//
//  Prop.swift
//  Backpack
//
//  Created by Sarfraz Basha on 18/03/2026.
//

import UIKit

/// A declarative description of how a single view enters and exits the stage.
///
/// Each ``Stageable`` view controller returns an array of `Prop`s. The ``StageVC``
/// animation engine uses them to choreograph entrance and exit transitions — sliding
/// views on from a screen edge or applying a custom off-screen transform.
///
/// ```swift
/// var props: [Prop] {
///     [
///         Prop(titleLabel, from: .top),
///         Prop(cardView,   from: .bottom, delay: 0.05),
///         Prop(avatar,     transform: .init(scaleX: 0, y: 0), delay: 0.1)
///     ]
/// }
/// ```
struct Prop {
    /// The view that will be animated on/off screen.
    let view: UIView
    /// The edge the view slides from. Mutually exclusive with ``transform``.
    let direction: Direction?
    /// A custom off-screen transform. Mutually exclusive with ``direction``.
    let transform: CGAffineTransform?
    /// Seconds to wait before this prop's animation starts, creating a stagger effect.
    let delay: TimeInterval

    /// A screen edge (or corner) that a ``Prop`` slides in from and out toward.
    enum Direction {
        case top, bottom, left, right
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// Creates a prop that slides in from a screen edge.
    /// - Parameters:
    ///   - view: The view to animate.
    ///   - direction: The edge the view enters from.
    ///   - delay: Stagger delay in seconds. Defaults to `0`.
    init(_ view: UIView, from direction: Direction, delay: TimeInterval = 0) {
        self.view = view
        self.direction = direction
        self.transform = nil
        self.delay = delay
    }

    /// Creates a prop with a custom off-screen transform (e.g. scale-to-zero).
    /// - Parameters:
    ///   - view: The view to animate.
    ///   - transform: The transform applied when the view is off-screen.
    ///   - delay: Stagger delay in seconds. Defaults to `0`.
    init(_ view: UIView, transform: CGAffineTransform, delay: TimeInterval = 0) {
        self.view = view
        self.direction = nil
        self.transform = transform
        self.delay = delay
    }

    /// Returns the transform that places this view off-screen,
    /// calculated from the view's current frame and the screen bounds.
    func offScreenTransform() -> CGAffineTransform {
        if let transform { return transform }
        guard let direction else { return .identity }

        let screen = UIScreen.main.bounds
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
