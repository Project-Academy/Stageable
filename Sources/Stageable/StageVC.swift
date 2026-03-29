//
//  StageVC.swift
//  Backpack
//
//  Created by Sarfraz Basha on 18/03/2026.
//

import UIKit

/**
 A container view controller that manages a stack of ``Stageable`` children,
 animating their ``Prop``s on and off screen with staggered spring transitions.

 `StageVC` replaces `UINavigationController` with a theatrical metaphor:
 child view controllers are *sets* whose UI elements (*props*) slide on
 from the wings. The container owns all animation timing — children only
 declare *what* moves and *where from*.

 Subclass `StageVC` to add app-specific chrome (backgrounds, status bar
 preferences, launch routing, etc.).

 ## Navigation API
 | Method | Behaviour |
 |---|---|
 | ``push(_:)`` | Animate out the current VC, push a new one onto the stack. |
 | ``pop()`` | Animate out the top VC, return to the one below it. |
 | ``popToRoot()`` | Return to the first VC in the stack. |
 | ``setRoot(_:)`` | Replace the entire stack with a single new root. |
 */
open class StageVC: UIViewController {

    //--------------------------------------
    // MARK: - VARIABLES -
    //--------------------------------------
    private var stack: [Stageable] = []
    private var isTransitioning = false
    /**
     Props owned by the container itself — animated on every transition alongside the child's props.
     Use these for persistent chrome (e.g. a tab bar or navigation overlay) that should move with each scene change.
     */
    open var props: [Prop] = []

    //--------------------------------------
    // MARK: - TRANSITIONS -
    //--------------------------------------

    /**
     Called just before the outgoing view controller's props begin their exit animation.
     Override to prepare any container-level state that depends on which VC is leaving.
     */
    open func vcWillTransition(from outgoing: Stageable) {}

    /**
     Called just before the incoming view controller's props begin their entrance animation.
     Override to prepare any container-level state that depends on which VC is arriving.
     */
    open func vcWillTransition(to incoming: Stageable) {}

    /**
     Called after all entrance animations for the incoming view controller have completed.
     Override to perform any post-transition cleanup or state updates.
     */
    open func vcDidTransition() {}

    //--------------------------------------
    // MARK: - NAVIGATION -
    //--------------------------------------

    /**
     Pushes a new ``Stageable`` view controller onto the stack.

     The current top VC's props animate off-screen, then the incoming VC's
     props animate in. Calls are ignored while a transition is in progress.
     */
    public func push(_ incoming: Stageable) {
        guard !isTransitioning else { return }
        guard let outgoing = stack.last else {
            installFirst(incoming)
            stack = [incoming]
            return
        }
        isTransitioning = true
        vcWillTransition(from: outgoing)
        animateOut(outgoing) { [weak self] in
            guard let self else { return }
            outgoing.view.removeFromSuperview()
            outgoing.willMove(toParent: nil)
            outgoing.removeFromParent()
            self.stack.append(incoming)
            vcWillTransition(to: incoming)
            self.animateIn(incoming) {
                self.isTransitioning = false
                self.vcDidTransition()
            }
        }
    }

    /**
     Pops the top view controller off the stack and returns to the previous one.

     Requires at least two view controllers on the stack. Ignored during a transition.
     */
    func pop() {
        guard !isTransitioning, stack.count >= 2 else { return }
        let outgoing = stack[stack.count - 1]
        let incoming = stack[stack.count - 2]
        isTransitioning = true
        vcWillTransition(from: outgoing)
        animateOut(outgoing) { [weak self] in
            guard let self else { return }
            outgoing.view.removeFromSuperview()
            outgoing.willMove(toParent: nil)
            outgoing.removeFromParent()
            self.stack.removeLast()
            vcWillTransition(to: incoming)
            self.animateIn(incoming) {
                self.isTransitioning = false
                self.vcDidTransition()
            }
        }
    }

    /**
     Pops all view controllers above the root and returns to it.

     All intermediate view controllers are removed from the parent. Ignored during a transition.
     */
    func popToRoot() {
        guard !isTransitioning, stack.count > 1 else { return }
        let outgoing = stack[stack.count - 1]
        let root = stack[0]
        isTransitioning = true
        vcWillTransition(from: outgoing)
        animateOut(outgoing) { [weak self] in
            guard let self else { return }
            for vc in self.stack.dropFirst() {
                vc.view.removeFromSuperview()
                vc.willMove(toParent: nil)
                vc.removeFromParent()
            }
            self.stack = [root]
            vcWillTransition(to: root)
            self.animateIn(root) {
                self.isTransitioning = false
                self.vcDidTransition()
            }
        }
    }

    /**
     Replaces the entire stack with a single new root view controller.

     All existing view controllers are removed. If the stack is empty the
     incoming VC is installed immediately without an exit animation.
     */
    public func setRoot(_ incoming: Stageable) {
        guard !isTransitioning else { return }
        guard let outgoing = stack.last else {
            installFirst(incoming)
            stack = [incoming]
            return
        }
        isTransitioning = true
        vcWillTransition(from: outgoing)
        animateOut(outgoing) { [weak self] in
            guard let self else { return }
            for vc in self.stack {
                vc.view.removeFromSuperview()
                vc.willMove(toParent: nil)
                vc.removeFromParent()
            }
            self.stack = [incoming]
            vcWillTransition(to: incoming)
            self.animateIn(incoming) {
                self.isTransitioning = false
                self.vcDidTransition()
            }
        }
    }

    //--------------------------------------
    // MARK: - ANIMATION ENGINE -
    //--------------------------------------
    /**
     Installs the first view controller onto an empty stage without an exit animation.

     Sets up the VC's view, calls ``prepareForEntrance()``, then animates all props (including
     the container's own) to their on-screen positions using staggered spring animations.
     Completion fires `didMove(toParent:)`, ``didFinishEntrance()``, and ``vcDidTransition()``.
     */
    private func installFirst(_ vc: Stageable) {
        vc.view.frame = view.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addChild(vc)
        view.addSubview(vc.view)

        vc.prepareForEntrance()
        vc.view.layoutIfNeeded()
        vcWillTransition(to: vc)
        let allProps = vc.props + self.props
        for prop in allProps {
            prop.view.transform = prop.offScreenTransform()
        }

        let inDuration: TimeInterval = 0.45

        if allProps.isEmpty {
            vc.didMove(toParent: self)
            vc.didFinishEntrance()
            vcDidTransition()
            return
        }

        let lastIndex = allProps.enumerated()
            .max(by: { $0.element.delay < $1.element.delay })!
            .offset

        for (i, prop) in allProps.enumerated() {
            let animator = UIViewPropertyAnimator(
                duration: inDuration,
                timingParameters: UISpringTimingParameters(duration: inDuration, bounce: 0.1, initialVelocity: .zero)
            )
            animator.addAnimations { prop.view.transform = .identity }
            if i == lastIndex {
                animator.addCompletion { [weak self, weak vc] _ in
                    guard let self, let vc else { return }
                    vc.didMove(toParent: self)
                    vc.didFinishEntrance()
                    self.vcDidTransition()
                }
            }
            animator.startAnimation(afterDelay: prop.delay)
        }
    }

    /**
     Animates all props of `vc` (plus the container's own) to their off-screen transforms.

     Invokes `completion` once every prop's animator has finished. If there are no props,
     `completion` is called synchronously.
     */
    private func animateOut(_ vc: Stageable, completion: @escaping () -> Void) {
        let outDuration: TimeInterval = 0.35
        let allProps = vc.props + self.props

        if allProps.isEmpty {
            completion()
            return
        }

        var completedCount = 0
        for prop in allProps {
            let animator = UIViewPropertyAnimator(
                duration: outDuration,
                timingParameters: UISpringTimingParameters(duration: outDuration, bounce: 0, initialVelocity: .zero)
            )
            animator.addAnimations { prop.view.transform = prop.offScreenTransform() }
            animator.addCompletion { _ in
                completedCount += 1
                if completedCount == allProps.count {
                    completion()
                }
            }
            animator.startAnimation(afterDelay: prop.delay)
        }
    }

    /**
     Adds `vc`'s view to the hierarchy and animates its props (plus the container's own) on-screen.

     Calls ``prepareForEntrance()`` before beginning the animations, and fires `didMove(toParent:)`,
     ``didFinishEntrance()``, and `completion` via the last animator's completion handler.
     If there are no props, those callbacks fire synchronously.
     */
    private func animateIn(_ vc: Stageable, completion: @escaping () -> Void) {
        vc.view.frame = view.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        if vc.parent == nil {
            addChild(vc)
        }
        view.addSubview(vc.view)

        let allProps = vc.props + self.props
        for prop in allProps {
            prop.view.transform = .identity
        }
        vc.prepareForEntrance()
     	
        vc.view.layoutIfNeeded()
        for prop in allProps {
            prop.view.transform = prop.offScreenTransform()
        }

        let inDuration: TimeInterval = 0.45

        if allProps.isEmpty {
            vc.didMove(toParent: self)
            vc.didFinishEntrance()
            completion()
            return
        }
     
        let lastIndex = allProps.enumerated()
            .max(by: { $0.element.delay < $1.element.delay })!
            .offset

        for (i, prop) in allProps.enumerated() {
            let animator = UIViewPropertyAnimator(
                duration: inDuration,
                timingParameters: UISpringTimingParameters(duration: inDuration, bounce: 0.1, initialVelocity: .zero)
            )
            animator.addAnimations {  
				prop.view.transform = .identity 
				for prop in self.props { 
					self.view.bringSubviewToFront(prop.view)
				}
			}
            if i == lastIndex {
                animator.addCompletion { [weak self, weak vc] _ in
                    guard let self, let vc else { return }
                    vc.didMove(toParent: self)
                    vc.didFinishEntrance()
                    completion()
                }
            }
            animator.startAnimation(afterDelay: prop.delay)
        }
    }
}
