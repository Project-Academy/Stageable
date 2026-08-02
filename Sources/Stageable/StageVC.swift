//
//  StageVC.swift
//  Stageable
//
//  Created by Sarfraz Basha on 18/03/2026.
//

import UIKit

/**
 The container. Owns a stack of ``Stageable`` screens, shows the top one, and
 animates between them.

 All stack decisions live in ``Navigator`` — a pure state machine the container
 consults; this class only moves views and fires callbacks, in the order the
 rebuild plan's A7 table fixes.

 Build state: skeleton. Parking, chrome, animated phases and appearance
 forwarding arrive in plan tasks 12–15; until the phases land, every transition
 is the F6 degenerate case — no animators, so it completes synchronously.
 */
open class StageVC: UIViewController {

    //--------------------------------------
    // MARK: - STATE -
    //--------------------------------------

    private var navigator = Navigator()

    /// A plan has been issued and has not yet landed (A7 step 9 clears this).
    private var inFlight = false

    /// A drain is on the call stack — re-entrant calls return immediately.
    private var draining = false

    //--------------------------------------
    // MARK: - READING THE STAGE -
    //--------------------------------------

    /// The DESTINATION top — during a transition, the incoming screen.
    public var top: (any Stageable)? { navigator.top }

    /// Destination depth, counted the same way.
    public var depth: Int { navigator.depth }

    /// Whether the screen is in the destination stack.
    public func contains(_ screen: any Stageable) -> Bool { navigator.contains(screen) }

    //--------------------------------------
    // MARK: - COMMANDS -
    //--------------------------------------

    /// Puts a screen on top. The covered screen stays stacked; Back returns to it.
    public func push(_ screen: any Stageable, completion: ((Outcome) -> Void)? = nil) {
        submit(.push(screen, completion: completion))
    }

    /// Removes the visible top, returning to the screen beneath. Always the top
    /// (plan D2): a non-top screen calling this is an app bug.
    public func pop(completion: ((Outcome) -> Void)? = nil) {
        submit(.pop(completion: completion))
    }

    /// Pops every screen down to the root.
    public func popToRoot(completion: ((Outcome) -> Void)? = nil) {
        submit(.popToRoot(completion: completion))
    }

    /// Replaces the visible top in place — the stack does not grow. For
    /// advance-style flows where the current screen is finished.
    public func replaceTop(with screen: any Stageable, completion: ((Outcome) -> Void)? = nil) {
        submit(.replaceTop(screen, completion: completion))
    }

    /// The stack is now this. Everything queued is discarded — and a queued
    /// `setRoot` is superseded, so the newest root wins (plan D6). An in-flight
    /// transition finishes first; it is not pre-empted.
    public func setRoot(_ screen: any Stageable, completion: ((Outcome) -> Void)? = nil) {
        submit(.setRoot(screen, completion: completion))
    }

    private func submit(_ command: Command) {
        let voided = navigator.enqueue(command)
        for (dropped, outcome) in voided { dropped.completion?(outcome) }
        drain()
    }

    //--------------------------------------
    // MARK: - THE PUMP -
    //--------------------------------------
    /**
     One drain (plan D4): gated on in-flight AND re-entrancy, and it loops.

     A synchronous transition — no animators, under F6 — lands inside `perform`,
     whose own step-9 drain is the re-entrant call swallowed by `draining`; the
     outer loop then continues, so nothing strands in the queue.
     */
    private func drain() {
        guard !inFlight, !draining else { return }
        draining = true
        defer { draining = false }

        while !inFlight {
            let (plan, settled) = navigator.next()
            for (command, outcome) in settled { command.completion?(outcome) }
            guard let plan else { break }
            perform(plan)
        }
    }

    //--------------------------------------
    // MARK: - THE PARKING LEDGER (A4) -
    //--------------------------------------
    /**
     Every view the container moves, it puts back — to the value recorded when
     it was moved, never to whatever it observes at restore time.

     Keyed by screen. An entry outlives a covering (the screen's views wait
     off-screen for the pop back) and is settled either by the enter phase or,
     for a screen leaving for good, at its release.
     */
    private struct ParkRecord {
        let view: UIView
        let restore: CGAffineTransform
    }
    private var ledger: [ObjectIdentifier: [ParkRecord]] = [:]

    /// Read the screen's props NOW, record what each view has, move it off.
    /// Parking twice would record the parked value as the restore value — the
    /// ledger refuses: an existing entry stands.
    private func park(_ screen: any Stageable) {
        let key = ObjectIdentifier(screen)
        guard ledger[key] == nil else { return }
        ledger[key] = screen.props.map { prop in
            let record = ParkRecord(view: prop.view, restore: prop.view.transform)
            prop.view.transform = prop.offScreenTransform()
            return record
        }
    }

    /// Put every parked view back to its recorded value and settle the entry.
    /// Restoring a screen with no entry is a no-op, not an error.
    private func restore(_ screen: any Stageable) {
        guard let records = ledger.removeValue(forKey: ObjectIdentifier(screen)) else { return }
        for record in records { record.view.transform = record.restore }
    }

    //--------------------------------------
    // MARK: - PERFORMING PLANS (A7) -
    //--------------------------------------

    private func perform(_ plan: Plan) {
        inFlight = true
        switch plan {
        case .transition(let outgoing, let incoming, let exit, let alsoLeaving, let completion):
            transition(outgoing: outgoing, incoming: incoming, exit: exit,
                       alsoLeaving: alsoLeaving, completion: completion)
        case .strike(let screens, let completion):
            strike(screens: screens, completion: completion)
        }
    }

    private func transition(outgoing: (any Stageable)?, incoming: any Stageable,
                            exit: Exit, alsoLeaving: [any Stageable],
                            completion: ((Outcome) -> Void)?) {
        // Adopt at plan-issue — and only if not already a child: re-adopting a
        // covered screen would open a second `willMove` and fire `didMove` twice.
        let adopting = incoming.parent !== self
        if adopting { addChild(incoming) }

        // Steps 1–5 exist only when something is leaving (first install skips them).
        if let outgoing {
            emitWillBegin(.exit, from: outgoing, to: incoming)                  // 1
            outgoing.willExit(exit)                                             // 2
            for screen in alsoLeaving { screen.willExit(.removed) }

            // 3 (appearance) — task 15.
            // 4: exit animators — task 14. Degenerate case: park and remove
            // immediately. A covered screen's entry outlives this transition.
            park(outgoing)
            outgoing.view.removeFromSuperview()

            outgoing.didExit(exit)                                              // 5
            for screen in alsoLeaving {
                screen.view.removeFromSuperview()
                screen.willMove(toParent: nil)
                screen.removeFromParent()
                screen.didExit(.removed)
                restore(screen)         // A4: leaving for good, put it all back
            }
            if exit == .removed {
                outgoing.willMove(toParent: nil)
                outgoing.removeFromParent()
                restore(outgoing)       // A4
            }
            emitDidEnd(.exit)
        }

        // 6 — the seam, in A7's exact order. Chrome (task 13) joins here.
        // Transform is reset before frame, or the translation is baked into
        // `center`; parked views are restored before layout, or a covered
        // screen's parked transform corrupts the frame the new park distance
        // is measured from.
        view.addSubview(incoming.view)
        incoming.view.transform = .identity
        incoming.view.frame = view.bounds
        incoming.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        restore(incoming)
        emitWillBegin(.enter, from: outgoing, to: incoming)
        incoming.willEnter()
        incoming.view.layoutIfNeeded()
        park(incoming)

        // 7: enter animators — task 14. Degenerate case: the entrance lands
        // immediately, which IS the restore.
        restore(incoming)

        // 8.
        if adopting { incoming.didMove(toParent: self) }
        incoming.didEnter()
        emitDidEnd(.enter)

        land(completion)                                                        // 9
    }

    private func strike(screens: [any Stageable], completion: ((Outcome) -> Void)?) {
        for screen in screens {
            screen.willExit(.removed)
            screen.view.removeFromSuperview()
            screen.willMove(toParent: nil)
            screen.removeFromParent()
            screen.didExit(.removed)
            restore(screen)             // A4: leaving for good, put it all back
        }
        // Chrome reconciles bare here (task 13) — a strike changes `depth`.
        land(completion)
    }

    /// A7 step 9: the one place a plan stops being in flight.
    private func land(_ completion: ((Outcome) -> Void)?) {
        inFlight = false
        completion?(.performed)
        drain()
        if !inFlight, navigator.queue.isEmpty { emitDidSettle() }
    }

    //--------------------------------------
    // MARK: - STAGE HOOKS & OBSERVERS -
    //--------------------------------------

    /// A phase is beginning. Override in a stage subclass; a host that owns a
    /// stage uses ``StageObserver`` instead. Called before observers.
    open func stageWillBegin(_ phase: Phase, from: (any Stageable)?, to: (any Stageable)?) { }

    /// The phase's last animator completed.
    open func stageDidEnd(_ phase: Phase) { }

    /// A plan landed, the queue is empty, and nothing is in flight.
    open func stageDidSettle() { }

    private struct WeakObserver { weak var value: (any StageObserver)? }
    private var observers: [WeakObserver] = []

    public func addObserver(_ observer: any StageObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
        observers.append(WeakObserver(value: observer))
    }

    public func removeObserver(_ observer: any StageObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
    }

    private func emitWillBegin(_ phase: Phase, from: (any Stageable)?, to: (any Stageable)?) {
        stageWillBegin(phase, from: from, to: to)
        for observer in observers { observer.value?.stageWillBegin(phase, from: from, to: to) }
    }

    private func emitDidEnd(_ phase: Phase) {
        stageDidEnd(phase)
        for observer in observers { observer.value?.stageDidEnd(phase) }
    }

    private func emitDidSettle() {
        stageDidSettle()
        for observer in observers { observer.value?.stageDidSettle() }
    }
}
