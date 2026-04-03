//
//  Stageable.swift
//  Backpack
//
//  Created by Sarfraz Basha on 18/03/2026.
//

import UIKit

/**
 A view controller that can be managed by a ``StageVC``.

 Conforming types declare their animated elements via ``props`` and
 optionally hook into ``prepareForEntrance()`` and ``didFinishEntrance()``
 for setup/teardown around transitions.

 Navigation convenience methods (``push(_:)``, ``pop()``, ``popToRoot()``)
 are provided automatically through the default extension.

 ```swift
 extension MyVC: Stageable {
     var props: [Prop] {
         [Prop(headerView, from: .top),
          Prop(contentView, from: .bottom, delay: 0.05)]
     }
 }
 ```
 */
public protocol Stageable: UIViewController {
    /// The views that participate in stage entrance/exit animations.
    var props: [Prop] { get }
    /**
     Called just before entrance animations begin. Use this to configure
     initial layout or state that the animation depends on.
     */
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

    /**
     Animates overlay props to or from their off-screen transforms.

     Only props with ``Prop/overlay`` set to `true` are affected.
     Use this for toggling UI visibility within the same VC
     (e.g. a focus/immersive mode) without a full stage transition.

     - Parameters:
       - visible: `true` to animate props on-screen, `false` to animate them off.
       - inDuration: Animation duration when showing. Defaults to `0.5`.
       - outDuration: Animation duration when hiding. Defaults to `0.35`.
       - stagger: Delay increment between successive props. Defaults to `0.04`.
     */
    func setPropsVisible(
        _ visible: Bool,
        inDuration: TimeInterval = 0.5,
        outDuration: TimeInterval = 0.35,
        stagger: TimeInterval = 0.04
    ) {
        let overlayProps = props.filter(\.overlay)
        guard !overlayProps.isEmpty else { return }

        // Compute off-screen transforms while all views are at identity
        let savedTransforms = overlayProps.map { $0.view.transform }
        for prop in overlayProps { prop.view.transform = .identity }
        let offScreenTransforms = overlayProps.map { $0.offScreenTransform() }
        for (prop, saved) in zip(overlayProps, savedTransforms) { prop.view.transform = saved }

        for (i, prop) in overlayProps.enumerated() {
            let offScreen = offScreenTransforms[i]
            if visible {
                prop.view.transform = offScreen
                prop.view.alpha = 0
                let animator = UIViewPropertyAnimator(
                    duration: inDuration,
                    timingParameters: UISpringTimingParameters(
                        duration: inDuration, bounce: 0.1, initialVelocity: .zero)
                )
                animator.addAnimations {
                    prop.view.transform = .identity
                    prop.view.alpha = 1
                }
                animator.startAnimation(afterDelay: stagger * Double(i))
            } else {
                let animator = UIViewPropertyAnimator(
                    duration: outDuration,
                    timingParameters: UISpringTimingParameters(
                        duration: outDuration, bounce: 0, initialVelocity: .zero)
                )
                animator.addAnimations {
                    prop.view.transform = offScreen
                    prop.view.alpha = 0
                }
                animator.startAnimation(afterDelay: stagger * Double(i))
            }
        }
    }
}
