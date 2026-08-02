//
//  Chrome.swift
//  Stageable
//
//  Views that outlive the screens, and the phases they ride.
//

import UIKit

//--------------------------------------
// MARK: - PHASE -
//--------------------------------------
/**
 The two halves of a transition: the outgoing screen leaves, then the incoming
 screen arrives. Each is one animated beat; a phase ends when all its animators
 complete, and a phase with no animators takes no time.
 */
public enum Phase: Sendable {
    case exit, enter
}

//--------------------------------------
// MARK: - CHROME -
//--------------------------------------
/**
 A view that outlives the screens and is present or absent by a rule, not by a
 screen's say-so — a header, a back button, a persistent toolbar.

 The container reconciles: it evaluates ``isPresent`` against the stage's
 DESTINATION state on every transition, and calls ``apply`` only when the answer
 changed. Which phase the change rides is derived, never configured — becoming
 absent rides `.exit`, becoming present rides `.enter`, and where there is no
 phase to ride (first install, a strike, `refreshChrome()`) it is applied bare.
 Chrome unchanged across a transition is not touched at all.
 */
public struct Chrome {

    /// The view the rule governs. The container keeps it above the screens.
    public let view: UIView

    /// The rule. Read the stage — `top`, `depth`, `contains` — not the view
    /// hierarchy; during a transition these already describe the destination.
    public let isPresent: @MainActor (StageVC) -> Bool

    /// Set values for the given presence. Do not animate: the container calls
    /// this inside the phase's animator so the change rides the phase's timing,
    /// or bare when there is no phase to ride.
    public let apply: @MainActor (Bool) -> Void

    public init(_ view: UIView,
                isPresent: @escaping @MainActor (StageVC) -> Bool,
                apply: @escaping @MainActor (Bool) -> Void) {
        self.view = view
        self.isPresent = isPresent
        self.apply = apply
    }

    /// A chrome whose `apply` is derived from a prop: present is `.identity`,
    /// absent is the prop's off-screen transform.
    @MainActor
    public init(_ prop: Prop, isPresent: @escaping @MainActor (StageVC) -> Bool) {
        self.init(prop.view, isPresent: isPresent) { present in
            prop.view.transform = present ? .identity : prop.offScreenTransform()
        }
    }
}

//--------------------------------------
// MARK: - STAGE OBSERVER -
//--------------------------------------
/**
 The stage-level hooks, for a host that OWNS a stage rather than being one —
 the `stage…` overrides require being the subclass, which a host is not.

 Observers are held weakly and called after the subclass override.
 */
@MainActor
public protocol StageObserver: AnyObject {
    func stageWillBegin(_ phase: Phase, from: (any Stageable)?, to: (any Stageable)?)
    func stageDidEnd(_ phase: Phase)
    /// A plan landed, the queue is empty, and nothing is in flight.
    func stageDidSettle()
}

public extension StageObserver {
    func stageWillBegin(_ phase: Phase, from: (any Stageable)?, to: (any Stageable)?) { }
    func stageDidEnd(_ phase: Phase) { }
    func stageDidSettle() { }
}
