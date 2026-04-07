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
 optionally hook into lifecycle methods for setup/teardown around transitions.

 ## What props handle automatically
 Each view listed in ``props`` is automatically animated on/off screen using
 spring-driven transforms. You don't need to write any animation code for these
 views — just declare them and the stage engine handles the rest.

 ## When to use the lifecycle hooks instead
 Use the lifecycle hooks for things that **can't** be expressed as a directional
 slide or custom transform on a single view:
 - **Alpha fades** (e.g. dimming overlays) — props animate via `transform`, not `alpha`.
 - **Layout changes** (e.g. collapsing a height constraint before entrance).
 - **State resets** (e.g. resetting scroll position or reloading data).
 - **Child view controllers** whose internal autolayout fights transform-based animation.
 - **Concurrent animations** that should run alongside the props transition
   (start a `UIView.animate` in the hook and it will run in parallel).

 ## HUD configuration

 Each ``Stageable`` VC can declare which container buttons it wants visible:
 - ``showsSettingsButton`` — defaults to `true`. Set `false` for immersive screens.
 - ``showsFocusButton`` — defaults to `false`. Return `true` for VCs that support focus mode.
 - ``focusToggled(_:)`` — called when the user toggles focus mode. React by hiding
   overlay elements and/or mutating ``showsSettingsButton``.

 ## Lifecycle order

 **Entrance** (push/pop arriving):
 1. ``prepareForEntrance()`` — configure initial state; layout is forced immediately after.
 2. Props animate from off-screen transforms to `.identity`.
 3. ``didFinishEntrance()`` — all prop animations have completed.

 **Exit** (push/pop departing):
 1. ``prepareForExit()`` — kick off any concurrent animations (e.g. fading a dimming view).
 2. Props animate from `.identity` to their off-screen transforms.
 3. View is removed from the hierarchy.

 ## Example
 ```swift
 extension MyVC: Stageable {
     var props: [Prop] {
         [Prop(headerView, from: .top),
          Prop(contentView, from: .bottom, delay: 0.05)]
     }

     func prepareForEntrance() {
         // Reset scroll position before the content slides in
         scrollView.contentOffset = .zero
     }

     func prepareForExit() {
         // Fade out an overlay that can't be expressed as a transform
         UIView.animate(withDuration: 0.35) { self.dimView.alpha = 0 }
     }
 }
 ```
 */
public protocol Stageable: UIViewController {

    /// The views that participate in stage entrance/exit animations.
    ///
    /// Each ``Prop`` declares a view, a direction (or custom transform), and an
    /// optional stagger delay. The stage engine automatically animates these views
    /// on and off screen — you do not need to write animation code for them.
    ///
    /// This property is evaluated each time a transition begins, so it can
    /// return different props based on current state (e.g. only include a panel
    /// view when it's on screen).
    var props: [Prop] { get }

    /// Called just before entrance animations begin.
    ///
    /// Use this to configure initial layout or state that the animation depends on.
    /// The view's layout is forced (`layoutIfNeeded`) immediately after this returns,
    /// so constraint changes made here will take effect before the first animation frame.
    ///
    /// Any `UIView.animate` calls made here will run **concurrently** with the
    /// props entrance animation.
    func prepareForEntrance()

    /// Called just before exit animations begin.
    ///
    /// Use this to kick off animations that should run concurrently with the props
    /// sliding off screen — for example, fading out a dimming view or collapsing
    /// a panel. The exit animation duration is ``StageVC/outDuration``.
    func prepareForExit()

    /// Called after all entrance animations have completed.
    ///
    /// Use this for work that should only happen once the VC is fully visible —
    /// for example, starting a loading indicator or beginning playback.
    func didFinishEntrance()

    /// Whether the container's settings button should be visible for this VC.
    ///
    /// Defaults to `true`. Set to `false` for full-screen experiences
    /// (e.g. login, settings) that manage their own chrome.
    /// This property is read by the container during transitions and after
    /// ``focusToggled(_:)`` — mutate it there to react to focus mode changes.
    var showsSettingsButton: Bool { get set }

    /// Whether the container's focus button should be visible for this VC.
    ///
    /// Defaults to `false`. Return `true` for VCs that support a focus/immersive
    /// mode (e.g. a document viewer that can hide its overlay controls).
    var showsFocusButton: Bool { get }

    /// Called by the container when the user toggles focus mode.
    ///
    /// Implement this to hide or show overlay elements in response.
    /// You may also mutate ``showsSettingsButton`` here — the container
    /// reads it after this method returns and animates accordingly.
    ///
    /// - Parameter isFocused: `true` when entering focus mode, `false` when exiting.
    func focusToggled(_ isFocused: Bool)
}

public extension Stageable {
    func prepareForEntrance() { }
    func prepareForExit() { }
    func didFinishEntrance() { }

    var showsSettingsButton: Bool {
        get { true }
        set { }
    }
    var showsFocusButton: Bool { false }
    func focusToggled(_ isFocused: Bool) { }

    /// The ``StageVC`` this view controller is currently on, if any.
    var stage: StageVC? { parent as? StageVC }
    /// Pushes a new view controller onto the stage stack.
    func push(_ vc: Stageable) { stage?.push(vc) }
    /// Pops this view controller off the stage stack, returning to the previous one.
    func pop() { stage?.pop() }
    /// Pops all view controllers down to the root of the stage stack.
    func popToRoot() { stage?.popToRoot() }
}
