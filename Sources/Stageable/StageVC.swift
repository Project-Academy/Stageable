//
//  StageVC.swift
//  Backpack
//
//  Created by Sarfraz Basha on 18/03/2026.
//

import UIKit

/// A container view controller that manages a stack of ``Stageable`` children,
/// animating their ``Prop``s on and off screen with staggered spring transitions.
///
/// `StageVC` replaces `UINavigationController` with a theatrical metaphor:
/// child view controllers are *sets* whose UI elements (*props*) slide on
/// from the wings. The container owns all animation timing — children only
/// declare *what* moves and *where from*.
///
/// Subclass `StageVC` to add app-specific chrome (backgrounds, status bar
/// preferences, launch routing, etc.).
///
/// ## Navigation API
/// | Method | Behaviour |
/// |---|---|
/// | ``push(_:)`` | Animate out the current VC, push a new one onto the stack. |
/// | ``pop()`` | Animate out the top VC, return to the one below it. |
/// | ``popToRoot()`` | Return to the first VC in the stack. |
/// | ``setRoot(_:)`` | Replace the entire stack with a single new root. |
open class StageVC: UIViewController {

    //--------------------------------------
    // MARK: - VARIABLES -
    //--------------------------------------
    private var stack: [Stageable] = []
    private var isTransitioning = false
    open var props: [Prop] = []

    //--------------------------------------
    // MARK: - TRANSITIONS -
    //--------------------------------------
    open func vcWillTransition() { }
    open func vcDidTransition() { }

    //--------------------------------------
    // MARK: - NAVIGATION -
    //--------------------------------------

    /// Pushes a new ``Stageable`` view controller onto the stack.
    ///
    /// The current top VC's props animate off-screen, then the incoming VC's
    /// props animate in. Calls are ignored while a transition is in progress.
    func push(_ incoming: Stageable) {
        guard !isTransitioning else { return }
        guard let outgoing = stack.last else {
            installFirst(incoming)
            stack = [incoming]
            return
        }
        isTransitioning = true
        vcWillTransition()
        animateOut(outgoing) { [weak self] in
            guard let self else { return }
            outgoing.view.removeFromSuperview()
            outgoing.willMove(toParent: nil)
            outgoing.removeFromParent()
            self.stack.append(incoming)
            self.animateIn(incoming) {
                self.isTransitioning = false
                self.vcDidTransition()
            }
        }
    }

    /// Pops the top view controller off the stack and returns to the previous one.
    ///
    /// Requires at least two view controllers on the stack. Ignored during a transition.
    func pop() {
        guard !isTransitioning, stack.count >= 2 else { return }
        let outgoing = stack[stack.count - 1]
        let incoming = stack[stack.count - 2]
        isTransitioning = true
        vcWillTransition()
        animateOut(outgoing) { [weak self] in
            guard let self else { return }
            outgoing.view.removeFromSuperview()
            outgoing.willMove(toParent: nil)
            outgoing.removeFromParent()
            self.stack.removeLast()
            self.animateIn(incoming) {
                self.isTransitioning = false
                self.vcDidTransition()
            }
        }
    }

    /// Pops all view controllers above the root and returns to it.
    ///
    /// All intermediate view controllers are removed from the parent. Ignored during a transition.
    func popToRoot() {
        guard !isTransitioning, stack.count > 1 else { return }
        let outgoing = stack[stack.count - 1]
        let root = stack[0]
        isTransitioning = true
        vcWillTransition()
        animateOut(outgoing) { [weak self] in
            guard let self else { return }
            for vc in self.stack.dropFirst() {
                vc.view.removeFromSuperview()
                vc.willMove(toParent: nil)
                vc.removeFromParent()
            }
            self.stack = [root]
            self.animateIn(root) {
                self.isTransitioning = false
                self.vcDidTransition()
            }
        }
    }

    /// Replaces the entire stack with a single new root view controller.
    ///
    /// All existing view controllers are removed. If the stack is empty the
    /// incoming VC is installed immediately without an exit animation.
    public func setRoot(_ incoming: Stageable) {
        guard !isTransitioning else { return }
        guard let outgoing = stack.last else {
            installFirst(incoming)
            stack = [incoming]
            return
        }
        isTransitioning = true
        vcWillTransition()
        animateOut(outgoing) { [weak self] in
            guard let self else { return }
            for vc in self.stack {
                vc.view.removeFromSuperview()
                vc.willMove(toParent: nil)
                vc.removeFromParent()
            }
            self.stack = [incoming]
            self.animateIn(incoming) {
                self.isTransitioning = false
                self.vcDidTransition()
            }
        }
    }

    //--------------------------------------
    // MARK: - ANIMATION ENGINE -
    //--------------------------------------

    private func installFirst(_ vc: Stageable) {
        vc.view.frame = view.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addChild(vc)
        view.addSubview(vc.view)

        vc.prepareForEntrance()
        vc.view.layoutIfNeeded()
        vcWillTransition()
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
            animator.addAnimations { prop.view.transform = .identity }
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
