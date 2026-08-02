//
//  Stageable.swift
//  Stageable
//
//  Created by Sarfraz Basha on 18/03/2026.
//

import UIKit

/**
 A view controller that can be managed by a ``StageVC``.

 Declare the views that ride the container's animations via ``props``; the
 container animates them on and off screen and puts every one of them back
 where it found it. Hook the four lifecycle methods for everything else.

 ## Lifecycle

 **Entering** (arriving on screen):
 1. ``willEnter()`` — the view is installed but nothing has animated. Configure
    state the entrance depends on; layout is forced immediately after.
 2. Props animate from their off-screen transforms to `.identity`.
 3. ``didEnter()`` — the entrance has landed. Note that a queued `setRoot` can
    still tear this screen down moments later, so unconditional side effects
    (starting a charge, posting analytics) belong behind your own checks.

 **Leaving** (departing the screen):
 1. ``willExit(_:)`` — carries an ``Exit`` saying whether the screen is merely
    ``Exit/covered`` (Back returns here; hold your state) or ``Exit/removed``
    (nothing returns here; release what you are holding).
 2. Props animate off. The screen's own concurrent animations run on the
    screen's own timing — the container neither observes nor waits for them.
 3. ``didExit(_:)`` — same `Exit`, after the departure has landed.

 ## Example
 ```swift
 extension MyVC: Stageable {
     var props: [Prop] {
         [Prop(headerView, from: .top),
          Prop(contentView, from: .bottom, delay: 0.05)]
     }

     func willEnter() {
         scrollView.contentOffset = .zero
     }

     func willExit(_ exit: Exit) {
         guard exit == .removed else { return }
         player.stop()
     }
 }
 ```
 */
public protocol Stageable: UIViewController {

    /// The views that ride the container's entrance/exit animations.
    ///
    /// Evaluated at each transition's seam, so it can reflect current state —
    /// e.g. only include a panel while it is on screen.
    var props: [Prop] { get }

    /// The view is installed; nothing has animated yet. Layout is forced
    /// (`layoutIfNeeded`) immediately after this returns.
    ///
    /// **Never set a transform on a prop view here.** Props are parked right
    /// after this returns, and the value recorded at park is the entrance
    /// TARGET — a decorative pre-pose becomes what the screen lands on.
    /// (Shipped bug: a scaleX(0.2) pre-pose here squished a login screen.)
    func willEnter()

    /// The entrance has landed — every prop is at `.identity`.
    func didEnter()

    /// The screen is leaving, and `exit` says whether it is coming back.
    func willExit(_ exit: Exit)

    /// The departure has landed, with the same `exit` as ``willExit(_:)``.
    func didExit(_ exit: Exit)
}

public extension Stageable {
    func willEnter() { }
    func didEnter() { }
    func willExit(_ exit: Exit) { }
    func didExit(_ exit: Exit) { }

    /// The ``StageVC`` this screen is on, if any.
    ///
    /// Walks the parent chain, so it resolves for a scene nested inside another
    /// container as well as for a direct child. Valid for any stacked screen,
    /// not just the visible one — a covered screen keeps its parent. A screen
    /// that has been popped, replaced or cleared is on no stage and returns nil.
    var stage: StageVC? {
        var current: UIViewController? = parent
        while let vc = current {
            if let stage = vc as? StageVC { return stage }
            current = vc.parent
        }
        return nil
    }

    /// Pushes a screen onto the stage this screen is on.
    /// Without a stage the command has nowhere to go: `completion(.discarded)`.
    func push(_ screen: any Stageable, completion: ((Outcome) -> Void)? = nil) {
        if let stage { stage.push(screen, completion: completion) }
        else { completion?(.discarded) }
    }

    /// Pops the visible top — see ``StageVC/pop(completion:)``.
    func pop(completion: ((Outcome) -> Void)? = nil) {
        if let stage { stage.pop(completion: completion) }
        else { completion?(.discarded) }
    }

    /// Replaces the visible top in place — the stack does not grow.
    func replaceTop(with screen: any Stageable, completion: ((Outcome) -> Void)? = nil) {
        if let stage { stage.replaceTop(with: screen, completion: completion) }
        else { completion?(.discarded) }
    }

    /// Pops everything down to the root.
    func popToRoot(completion: ((Outcome) -> Void)? = nil) {
        if let stage { stage.popToRoot(completion: completion) }
        else { completion?(.discarded) }
    }
}
