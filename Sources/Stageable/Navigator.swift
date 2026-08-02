//
//  Navigator.swift
//  Stageable
//
//  The stack, the queue, and what a command means for them.
//
//  This half makes no decisions about views: it never installs, animates or
//  measures anything, and it never touches a view hierarchy. Push, pop,
//  supersession, covered-versus-removed and completion delivery are a state
//  machine, and entangling them with view work is why this framework went so
//  long without a test.
//

import UIKit

//--------------------------------------
// MARK: - EXIT -
//--------------------------------------
/**
 Why a screen is leaving — the one fact it cannot work out for itself, because
 the stack belongs to the navigator.

 Five commands collapse to two outcomes deliberately: a screen never learns the
 navigator's vocabulary, so a sixth would change nothing here.
 */
public enum Exit: Sendable {
    /// Something was put on top. Still in the stack; Back returns here.
    case covered
    /// Out of the stack. Nothing returns here — release what you are holding.
    case removed
}

//--------------------------------------
// MARK: - OUTCOME -
//--------------------------------------
/**
 What became of a command.

 A completion saying only "something happened" is a trap: a
 `push(payment) { beginCharge() }` discarded by a logout would start the charge
 over the login screen. The caller is told which of the three it was.
 */
public enum Outcome: Sendable {
    /// It ran.
    case performed
    /// Valid, but there was nothing to do — `pop` at the root.
    case noop
    /// A later `setRoot` made it void, or it named a screen already staged.
    case discarded
}

//--------------------------------------
// MARK: - COMMAND -
//--------------------------------------
/// A navigation request, held until the stage can perform it.
public enum Command {
    case push(any Stageable, completion: ((Outcome) -> Void)?)
    case pop(completion: ((Outcome) -> Void)?)
    case popToRoot(completion: ((Outcome) -> Void)?)
    case replaceTop(any Stageable, completion: ((Outcome) -> Void)?)
    case setRoot(any Stageable, completion: ((Outcome) -> Void)?)

    var completion: ((Outcome) -> Void)? {
        switch self {
        case .push(_, let c), .replaceTop(_, let c), .setRoot(_, let c): return c
        case .pop(let c), .popToRoot(let c): return c
        }
    }
}

//--------------------------------------
// MARK: - PLAN -
//--------------------------------------
/// What one command turned out to mean.
enum Plan {
    /// Something leaves the screen and something arrives.
    case transition(outgoing: (any Stageable)?,
                    incoming: any Stageable,
                    exit: Exit,
                    alsoLeaving: [any Stageable],
                    completion: ((Outcome) -> Void)?)

    /// Screens leave the stack; nothing on screen changes. This is what
    /// `setRoot` means when it names the screen already showing — the "go home"
    /// button holding one instance. Without it the container would strike that
    /// screen and re-present it, telling it that it left when it never did.
    case strike(screens: [any Stageable], completion: ((Outcome) -> Void)?)

    var completion: ((Outcome) -> Void)? {
        switch self {
        case .transition(_, _, _, _, let c), .strike(_, let c): return c
        }
    }
}

//--------------------------------------
// MARK: - NAVIGATOR -
//--------------------------------------
/// The stack and the queue. Pure: no views, no animation, no timing.
struct Navigator {

    /// The DESTINATION stack — mutated when a plan is issued, not when it lands,
    /// so during a transition it already describes where the stage is going.
    private(set) var stack: [any Stageable] = []
    private(set) var queue: [Command] = []

    var top: (any Stageable)? { stack.last }
    var depth: Int { stack.count }

    func contains(_ screen: any Stageable) -> Bool {
        stack.contains { $0 === screen }
    }

    /**
     Add a command, returning anything it voided.

     A `setRoot` clears the queue HERE, not in `next()`: "the stack is now this"
     supersedes whatever was queued — including an older `setRoot`, so the newest
     root always wins. Clearing at consume time was FIFO, which performed the
     older root and discarded the newer.

     The container fires the returned completions (`.discarded`) before draining.
     */
    mutating func enqueue(_ command: Command) -> [(Command, Outcome)] {
        var voided: [(Command, Outcome)] = []
        if case .setRoot = command {
            voided = queue.map { ($0, .discarded) }
            queue.removeAll()
        }
        queue.append(command)
        return voided
    }

    /**
     Consume commands until one implies work.

     Returns that plan, plus every command settled along the way and what became
     of it. Nothing is invoked here: a pure type reports what is owed and lets the
     container discharge it — which also stops a completion re-entering `enqueue`
     during a mutating call on the same storage.
     */
    mutating func next() -> (plan: Plan?, settled: [(Command, Outcome)]) {
        var settled: [(Command, Outcome)] = []

        while !queue.isEmpty {
            let command = queue.removeFirst()
            switch command {

            case .push(let incoming, _):
                // The same instance twice would have the stage strike a screen
                // and immediately re-present it, and a later pop would release
                // one that is still on stage.
                guard !contains(incoming) else {
                    settled.append((command, .discarded))
                    continue
                }
                let outgoing = stack.last
                stack.append(incoming)
                return (.transition(outgoing: outgoing, incoming: incoming,
                                    exit: outgoing == nil ? .removed : .covered,
                                    alsoLeaving: [], completion: command.completion), settled)

            case .pop:
                guard stack.count >= 2 else {
                    settled.append((command, .noop))
                    continue
                }
                let outgoing = stack.removeLast()
                return (.transition(outgoing: outgoing, incoming: stack[stack.count - 1],
                                    exit: .removed, alsoLeaving: [],
                                    completion: command.completion), settled)

            case .popToRoot:
                guard stack.count > 1 else {
                    settled.append((command, .noop))
                    continue
                }
                let outgoing = stack.removeLast()
                let alsoLeaving = Array(stack.dropFirst())
                stack = [stack[0]]
                return (.transition(outgoing: outgoing, incoming: stack[0], exit: .removed,
                                    alsoLeaving: alsoLeaving,
                                    completion: command.completion), settled)

            case .replaceTop(let incoming, _):
                guard let outgoing = stack.last else {
                    stack = [incoming]
                    return (.transition(outgoing: nil, incoming: incoming, exit: .removed,
                                        alsoLeaving: [], completion: command.completion), settled)
                }
                // Naming the screen already showing changes nothing.
                guard outgoing !== incoming else {
                    settled.append((command, .noop))
                    continue
                }
                // No screen may appear twice in the stack.
                guard !contains(incoming) else {
                    settled.append((command, .discarded))
                    continue
                }
                stack[stack.count - 1] = incoming
                return (.transition(outgoing: outgoing, incoming: incoming, exit: .removed,
                                    alsoLeaving: [], completion: command.completion), settled)

            case .setRoot(let incoming, _):
                // The queue was already cleared at enqueue — anything here now
                // arrived AFTER the setRoot and stays.
                let wasShowing = stack.last === incoming
                let leaving = stack.filter { $0 !== incoming }
                stack = [incoming]

                if wasShowing {
                    // Already the only thing on the stack: nothing to strike and
                    // nothing to show. A `.strike` with no screens would report
                    // `.performed` for a command that did nothing.
                    guard !leaving.isEmpty else {
                        settled.append((command, .noop))
                        continue
                    }
                    // Nothing enters or exits the screen; the rest just go.
                    return (.strike(screens: leaving, completion: command.completion), settled)
                }
                return (.transition(outgoing: leaving.last, incoming: incoming, exit: .removed,
                                    alsoLeaving: Array(leaving.dropLast()),
                                    completion: command.completion), settled)
            }
        }
        return (nil, settled)
    }
}
