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
    // MARK: - TIMING -
    //--------------------------------------

    /// Duration of the exit phase. Defaults lifted from 2.2.0.
    public var exitDuration: TimeInterval = 0.35

    /// Duration of the enter phase.
    public var enterDuration: TimeInterval = 0.45

    /**
     The animation primitive every phase runs on: one spring, one delay, one
     completion. Internal so tests can substitute a stub — F6 is a claim about
     completion topology, not about the clock.
     */
    var animate: (_ duration: TimeInterval, _ delay: TimeInterval, _ bounce: CGFloat,
                  _ animations: @escaping () -> Void,
                  _ completion: @escaping () -> Void) -> Void = { duration, delay, bounce, animations, completion in
        let animator = UIViewPropertyAnimator(
            duration: duration,
            timingParameters: UISpringTimingParameters(duration: duration, bounce: bounce,
                                                       initialVelocity: .zero))
        animator.addAnimations(animations)
        animator.addCompletion { _ in completion() }
        animator.startAnimation(afterDelay: delay)
    }

    /// One view, one destination, one stagger delay — a phase is N of these.
    private struct Move {
        let view: UIView
        let target: CGAffineTransform
        let delay: TimeInterval
    }

    /**
     Run one phase: start every animator, call `completion` when the last one
     completes. A phase with no animators takes no time — `completion` runs
     synchronously and ``animate`` is never touched (F6).
     */
    private func runPhase(_ phase: Phase, moves: [Move],
                          chrome chromeRiding: [Chrome], chromePresent: Bool,
                          completion: @escaping () -> Void) {
        var animators: [(delay: TimeInterval, animations: () -> Void)] = moves.map { move in
            (move.delay, { move.view.transform = move.target })
        }
        if !chromeRiding.isEmpty {
            animators.append((0, { self.applyChrome(chromeRiding, present: chromePresent) }))
        }
        guard !animators.isEmpty else { return completion() }

        let duration = phase == .exit ? exitDuration : enterDuration
        let bounce: CGFloat = phase == .exit ? 0 : 0.1
        var remaining = animators.count
        for entry in animators {
            animate(duration, entry.delay, bounce, entry.animations) {
                remaining -= 1
                if remaining == 0 { completion() }
            }
        }
    }

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
    // MARK: - CHROME -
    //--------------------------------------
    /**
     Views that outlive the screens (plan D1). The container owns them: their
     views live on the stage above every screen, their presence is one recorded
     Bool reconciled against destination state, and the phase a change rides is
     derived from its direction — absent rides `.exit`, present rides `.enter`,
     and where there is no phase to ride it is applied bare.
     */
    public private(set) var chrome: [Chrome] = []

    /// Last-applied presence, keyed by chrome view (F1: reconcile against the
    /// record, never against what the view currently looks like).
    private var chromePresence: [ObjectIdentifier: Bool] = [:]

    /// A `refreshChrome()` that arrived mid-transition, honoured at settle.
    private var chromeRefreshPending = false

    /// Replaces the chrome set. A departing chrome is put back first (A4): a
    /// chrome the container last applied absent is applied present again before
    /// its view leaves the stage.
    public func setChrome(_ newChrome: [Chrome]) {
        let newKeys = Set(newChrome.map { ObjectIdentifier($0.view) })
        for old in chrome where !newKeys.contains(ObjectIdentifier(old.view)) {
            let key = ObjectIdentifier(old.view)
            if chromePresence[key] == false { old.apply(true) }
            chromePresence[key] = nil
            old.view.removeFromSuperview()
        }
        chrome = newChrome
        for item in chrome where item.view.superview !== view {
            view.addSubview(item.view)
        }
        raiseChrome()
        reconcileChrome()
    }

    /// Re-evaluates presence now — for rules that read state outside the stage.
    /// During a transition the reconcile is deferred to settle; the transition
    /// itself already reconciles against its destination.
    public func refreshChrome() {
        guard !inFlight else { chromeRefreshPending = true; return }
        reconcileChrome()
    }

    /// Bare reconcile: evaluate, apply what changed, update the record.
    private func reconcileChrome() {
        for item in chrome {
            let key = ObjectIdentifier(item.view)
            let desired = item.isPresent(self)
            guard chromePresence[key] != desired else { continue }
            chromePresence[key] = desired
            item.apply(desired)
        }
    }

    /// The changes this transition must carry, split by the phase they ride.
    /// Evaluated once — the destination is fixed from plan-issue.
    private func chromeChanges() -> (absent: [Chrome], present: [Chrome]) {
        var absent: [Chrome] = [], present: [Chrome] = []
        for item in chrome {
            let key = ObjectIdentifier(item.view)
            let desired = item.isPresent(self)
            guard chromePresence[key] != desired else { continue }
            if desired { present.append(item) } else { absent.append(item) }
        }
        return (absent, present)
    }

    private func applyChrome(_ changes: [Chrome], present: Bool) {
        for item in changes {
            chromePresence[ObjectIdentifier(item.view)] = present
            item.apply(present)
        }
    }

    private func raiseChrome() {
        for item in chrome { view.bringSubviewToFront(item.view) }
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
        let delay: TimeInterval
    }
    private var ledger: [ObjectIdentifier: [ParkRecord]] = [:]

    /// Read the screen's props NOW and record what each view has. Returns the
    /// off-screen moves — the caller either animates them (exit phase) or
    /// applies them bare (the seam). Parking twice would record the parked
    /// value as the restore value — the ledger refuses: an existing entry stands.
    private func parkRecording(_ screen: any Stageable) -> [Move] {
        let key = ObjectIdentifier(screen)
        guard ledger[key] == nil else { return [] }
        var moves: [Move] = []
        ledger[key] = screen.props.map { prop in
            moves.append(Move(view: prop.view, target: prop.offScreenTransform(), delay: prop.delay))
            return ParkRecord(view: prop.view, restore: prop.view.transform, delay: prop.delay)
        }
        return moves
    }

    /// The moves that bring a parked screen's views back to their recorded
    /// values. The entry is settled separately, when those moves have landed.
    private func restoreMoves(_ screen: any Stageable) -> [Move] {
        guard let records = ledger[ObjectIdentifier(screen)] else { return [] }
        return records.map { Move(view: $0.view, target: $0.restore, delay: $0.delay) }
    }

    /// Put every parked view back to its recorded value, bare, and settle the
    /// entry. Restoring a screen with no entry is a no-op, not an error.
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

        // The chrome this transition carries, split by the phase each change
        // rides. Evaluated once — the destination is fixed from plan-issue.
        let chromeRiding = chromeChanges()

        // Steps 1–5 exist only when something is leaving. First install skips
        // them — its chrome has no exit phase to ride, so it reconciles bare
        // before the seam (absent chrome must not appear over the first screen).
        guard let outgoing else {
            applyChrome(chromeRiding.absent, present: false)
            applyChrome(chromeRiding.present, present: true)
            enterThroughSeam(from: nil, incoming: incoming, adopting: adopting,
                             chromeEntering: [], completion: completion)
            return
        }

        emitWillBegin(.exit, from: outgoing, to: incoming)                      // 1
        outgoing.willExit(exit)                                                 // 2
        for screen in alsoLeaving { screen.willExit(.removed) }

        // 3 — appearance, gated on the container's own visibility (D9).
        let forwarding = containerVisible
        if forwarding { outgoing.beginAppearanceTransition(false, animated: true) }

        // 4: the exit phase — the outgoing screen's props park, and chrome
        // becoming absent rides along. A covered screen's ledger entry
        // outlives this transition; the pop back restores it.
        let parkingMoves = parkRecording(outgoing)
        runPhase(.exit, moves: parkingMoves,
                 chrome: chromeRiding.absent, chromePresent: false) { [weak self] in
            guard let self else { return }
            outgoing.view.removeFromSuperview()
            if forwarding { outgoing.endAppearanceTransition() }

            outgoing.didExit(exit)                                              // 5
            for screen in alsoLeaving {
                screen.view.removeFromSuperview()
                screen.willMove(toParent: nil)
                screen.removeFromParent()
                screen.didExit(.removed)
                self.restore(screen)    // A4: leaving for good, put it all back
            }
            if exit == .removed {
                outgoing.willMove(toParent: nil)
                outgoing.removeFromParent()
                self.restore(outgoing)  // A4
            }
            self.emitDidEnd(.exit)

            self.enterThroughSeam(from: outgoing, incoming: incoming, adopting: adopting,
                                  chromeEntering: chromeRiding.present, completion: completion)
        }
    }

    /// A7 steps 6–9: the seam, the enter phase, the landing.
    private func enterThroughSeam(from outgoing: (any Stageable)?, incoming: any Stageable,
                                  adopting: Bool, chromeEntering: [Chrome],
                                  completion: ((Outcome) -> Void)?) {
        // 6 — the seam, in A7's exact order. Transform is reset before frame,
        // or the translation is baked into `center`; parked views are restored
        // before layout, or a covered screen's parked transform corrupts the
        // frame the new park distance is measured from.
        view.addSubview(incoming.view)
        incoming.view.transform = .identity
        incoming.view.frame = view.bounds
        incoming.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        raiseChrome()
        restore(incoming)
        let forwarding = containerVisible                                   // D9
        if forwarding { incoming.beginAppearanceTransition(true, animated: true) }
        emitWillBegin(.enter, from: outgoing, to: incoming)
        incoming.willEnter()
        incoming.view.layoutIfNeeded()

        // Read props and park them: record, then jump off-screen bare — the
        // audience only ever sees the entrance.
        let parkingMoves = parkRecording(incoming)
        for move in parkingMoves { move.view.transform = move.target }

        // 7: the enter phase — everything parked comes back to its recorded
        // value, and chrome becoming present rides along.
        runPhase(.enter, moves: restoreMoves(incoming),
                 chrome: chromeEntering, chromePresent: true) { [weak self] in
            guard let self else { return }
            self.ledger.removeValue(forKey: ObjectIdentifier(incoming))    // settled by the phase

            // 8.
            if forwarding { incoming.endAppearanceTransition() }
            if adopting { incoming.didMove(toParent: self) }
            incoming.didEnter()
            self.emitDidEnd(.enter)

            self.land(completion)                                           // 9
        }
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
        // Chrome reconciles bare — a strike changes `depth`, which
        // `isPresent` may read, and there is no phase to ride.
        reconcileChrome()
        land(completion)
    }

    /// A7 step 9: the one place a plan stops being in flight.
    private func land(_ completion: ((Outcome) -> Void)?) {
        inFlight = false
        completion?(.performed)
        drain()
        if !inFlight, navigator.queue.isEmpty {
            if chromeRefreshPending {
                chromeRefreshPending = false
                reconcileChrome()
            }
            emitDidSettle()
        }
    }

    //--------------------------------------
    // MARK: - APPEARANCE (A7 / D5 / D9) -
    //--------------------------------------
    /**
     UIKit forwards appearance on containment, and a covered screen keeps its
     parent — so automatic forwarding cannot deliver `viewWillDisappear` to a
     screen whose view leaves while it stays a child. The container therefore
     owns ALL child appearance.
     */
    open override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }

    /**
     Whether the container itself is on screen — between its own
     `viewWillAppear` and `viewDidDisappear`.

     Child appearance is delivered only while true (D9): a screen pushed into
     an off-screen container gets its appearance when the container appears,
     via the forwarding below — not at the push, which would double-deliver.
     */
    private var containerVisible = false

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        containerVisible = true
        top?.beginAppearanceTransition(true, animated: animated)
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        top?.endAppearanceTransition()
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        top?.beginAppearanceTransition(false, animated: animated)
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        top?.endAppearanceTransition()
        containerVisible = false
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
