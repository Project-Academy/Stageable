//
//  Stageable.swift
//  Backpack
//
//  Created by Sarfraz Basha on 18/03/2026.
//

import UIKit

/// A view controller that can be managed by a ``StageVC``.
///
/// Conforming types declare their animated elements via ``props`` and
/// optionally hook into ``prepareForEntrance()`` and ``didFinishEntrance()``
/// for setup/teardown around transitions.
///
/// Navigation convenience methods (``push(_:)``, ``pop()``, ``popToRoot()``)
/// are provided automatically through the default extension.
///
/// ```swift
/// extension MyVC: Stageable {
///     var props: [Prop] {
///         [Prop(headerView, from: .top),
///          Prop(contentView, from: .bottom, delay: 0.05)]
///     }
/// }
/// ```
public protocol Stageable: UIViewController {
    /// The views that participate in stage entrance/exit animations.
    var props: [Prop] { get }
    /// Called just before entrance animations begin. Use this to configure
    /// initial layout or state that the animation depends on.
    func prepareForEntrance()
    /// Called after all entrance animations have completed.
    func didFinishEntrance()
}

public extension Stageable {
    func prepareForEntrance() { }
    func didFinishEntrance() { }

    /// The ``StageVC`` this view controller is currently on, if any.
    var stage: StageVC? { parent as? StageVC }
    /// Pushes a new view controller onto the stage stack.
    func push(_ vc: Stageable) { stage?.push(vc) }
    /// Pops this view controller off the stage stack, returning to the previous one.
    func pop() { stage?.pop() }
    /// Pops all view controllers down to the root of the stage stack.
    func popToRoot() { stage?.popToRoot() }
}
