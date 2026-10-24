# Stageable

A UIKit navigation container that replaces `UINavigationController`. A **stage** owns a stack of screens and shows the top one; screens declare **props** — the views that ride the stage's animations — and the stage animates between screens in a fixed, tested callback order.

Screens declare *what* moves and *from where*. The stage decides *when*.

Inside, the framework is two halves: a pure state machine (`Navigator` — the stack, the queue, and what a command means for them) and a container (`StageVC`) that only moves views and fires callbacks. The state machine never touches a view, which is why this package has real tests.

---

## Who owns what

| The stage owns | The screen owns |
|---|---|
| **The stack** — `push`, `pop`, `popToRoot`, `replaceTop`, `setRoot`. Nothing else adds or removes a screen. | **Its props** — which views move, from which edge, after what delay. Data, not code. |
| **Transition timing** — `exitDuration` (0.35), `enterDuration` (0.45), spring, stagger, ordering. | **Its own content and state**, for as long as it is on the stack. |
| **Chrome** — views that outlive the screens, present or absent by a rule, kept above every screen. | **Its lifecycle hooks** — the things a transform can't express: fades, layout changes, resets. |
| **Every view it moves** — each is put back to the value recorded when it was moved, never to what it observes later. | |

**What the stage must not know:** what identity is, what a session is, or what ought to be on it. It is handed a screen and shows it. That ignorance is why the same container can carry a login screen and a document viewer — and why the root decision belongs in the app, not here.

---

## Usage

### Conform to `Stageable`

```swift
extension ProfileVC: Stageable {
    var props: [Prop] {
        [Prop(headerView,  from: .top),
         Prop(avatarView,  from: .left,   delay: 0.05),
         Prop(contentView, from: .bottom, delay: 0.1)]
    }
}
```

Direction props (`.top`, `.bottom`, `.left`, `.right`, and the corners) slide fully off their **superview**; `Prop(view, transform:)` expresses anything else. Off-screen travel is measured in the superview's space, so props inside inset containers, inner stages, and non-fullscreen windows all travel the correct distance. `overlay:` is app-readable metadata the engine ignores — filter your own `props` declaration with it (e.g. a focus mode) instead of keeping a parallel list that can drift.

`props` is read at each transition's seam, so it can vary with state. The stage restores parked views from its own ledger — a screen whose `props` changed while covered still gets every originally-parked view put back.

### Navigate

From any stacked screen (covered ones included — they keep their parent, so `stage` resolves):

```swift
push(DetailVC())          // covers this screen; Back returns here
pop()                     // removes the visible top — ALWAYS the top, not the caller
replaceTop(with: next)    // advance-style: the stack does not grow
popToRoot()
stage?.setRoot(HomeVC())  // the stack is now this; everything queued is discarded
```

Every command settles exactly once, saying which of three fates it took:

```swift
stage?.push(payment) { outcome in
    switch outcome {
    case .performed: beginCharge()   // it ran
    case .noop:      break           // valid, nothing to do — a pop at the root
    case .discarded: break           // a setRoot voided it, or it named a staged screen
    }
}
```

No command is dropped because the stage is busy — commands queue and run in order. A `setRoot` discards everything queued (an in-flight transition still finishes first), and the **newest** queued `setRoot` wins.

### Screen lifecycle

```swift
func willEnter()              // installed, nothing animated yet; layout is forced after
func didEnter()               // the entrance landed
func willExit(_ exit: Exit)   // .covered = Back returns here; .removed = release everything
func didExit(_ exit: Exit)    // same Exit, after the departure landed
```

`Exit` is the one fact a screen cannot work out for itself, because the stack belongs to the navigator. A queued `setRoot` can tear a screen down moments after `didEnter()` — unconditional side effects belong behind your own checks.

Appearance (`viewWillAppear` …) is forwarded by the stage, matching `UINavigationController`: covered screens get `viewWillDisappear`/`viewDidDisappear` even though they stay parented, and a screen pushed while the stage is off-screen receives its appearance when the stage appears.

### Chrome

```swift
stage.setChrome([
    Chrome(backButton, isPresent: { $0.depth > 1 }) { present in
        backButton.alpha = present ? 1 : 0
    },
    Chrome(Prop(headerBar, from: .top), isPresent: { _ in true }),  // apply derived from the prop
])
```

The stage reconciles: `isPresent` is evaluated against the **destination** state on every transition, `apply` runs only when the answer changed, and the change rides the phase its direction implies — becoming absent leaves with the outgoing screen, becoming present arrives with the incoming one. `apply` sets values, never animates; the stage calls it inside its own animator, or bare when there is no phase to ride (first install, strikes, `refreshChrome()`). For rules that read state outside the stage, call `refreshChrome()`.

Ride-along chrome — a view that should move with *every* scene change, not just when its presence flips — declares `riding: .everyTransition`: while present it leaves with each outgoing screen and returns with each incoming one. Both `setChrome` and `refreshChrome` defer to settle if called mid-transition (latest wins).

### Stage hooks

A subclass overrides; a host that *owns* a stage observes (weakly) instead:

```swift
class Shell: StageVC {
    override func stageWillBegin(_ phase: Phase, from: (any Stageable)?, to: (any Stageable)?) { }
    override func stageDidEnd(_ phase: Phase) { }
    override func stageDidSettle() { }   // a plan landed, queue empty, nothing in flight
}
// or: stage.addObserver(self)          // StageObserver
```

Read state from the stage, never the view hierarchy: `top`, `depth`, `contains(_:)` — all describe the **destination** during a transition. `isTransitioning` exists for tap-guards (a double-tapped close button is two honest pops without one); never poll it — anything that waits belongs on a completion or `stageDidSettle()`.

---

## Adopting it correctly — the window-root model

### 1. The window root is the stage, and it never changes

Install it once and leave it. Login and Home are both *screens on it* — not alternative window roots. Everything that reaches through the window root — deep links, share-sheet handoffs, topmost-VC walks — keeps working across a login and a logout, because the root outlives both.

### 2. Install the first screen in `viewIsAppearing`

Not `viewDidLoad`. Props are measured against real geometry, and in `viewDidLoad` there isn't any.

```swift
private var pendingRoot: (any Stageable)?
private var didInstallRoot = false

override func viewIsAppearing(_ animated: Bool) {
    super.viewIsAppearing(animated)
    guard !didInstallRoot else { return }
    didInstallRoot = true                 // BOTH branches — this never fires again
    guard let root = pendingRoot else { reconcileRoot(); return }
    pendingRoot = nil
    setRoot(root)
}
```

### 3. One reconcile, deriving the destination from the session

The root's destination is a pure function of "who is signed in". Login success and logout **call the reconcile**; they never name a destination.

```swift
enum RootIntent { case content, login }
private var installedRoot: RootIntent?

func reconcileRoot() {
    let desired: RootIntent = hasPersistedIdentity ? .content : .login
    guard installedRoot != desired else { return }
    guard let screen = screen(for: desired) else { return }   // record only once it exists
    installedRoot = desired
    guard didInstallRoot else { pendingRoot = screen; return }
    setRoot(screen)
}
```

### 4. Compare a stored **intent**, never the view

`installedRoot != desired` — not `top is HomeVC`, not `children.contains { $0 is LoginVC }`. Both shipped as bugs, in opposite directions (see Smell 1).

### 5. Use a synchronous identity predicate

`Session.storage.loggedInUser != nil` and friends are already in memory. Awaiting the root decision just delays first paint and invites a stash-and-defer dance.

### 6. Persistent UI goes on the stage as `Chrome`

Not as a view a screen manages, and not toggled from transition hooks — declare the rule and let the stage reconcile it.

### 7. Add a second stage only for a persistent **region**

A sidebar beside a detail pane needs its own stage, because `push` replaces the whole of a stage's view; a host VC owns the inner stage and observes it. Not a reason for a second stage: app size, "these change on different schedules", or content that can't be chosen until a fetch returns (stage a placeholder screen instead).

---

## Migrating from 2.2.0

2.4.0 is breaking. The renames are mechanical; the behaviour changes are not — read the second table.

| 2.2.0 | 2.4.0 |
|---|---|
| `prepareForEntrance()` | `willEnter()` |
| `didFinishEntrance()` | `didEnter()` |
| `prepareForExit()` | `willExit(_ exit: Exit)` — now says whether you're coming back |
| `vcWillTransition(from:)` / `(to:)` | `stageWillBegin(_ phase:from:to:)` |
| `vcDidTransition()` | `stageDidEnd(.enter)` per transition, or `stageDidSettle()` for queue-empty |
| `whenSettled { }` | delete it — commands queue; just issue the command |
| container `props` | `setChrome(_:)` — ride-along views use `riding: .everyTransition` |
| `replaceTop(_:)` | `replaceTop(with:)` |
| `popToRoot { }` (`() -> Void`) | completion is `(Outcome) -> Void` |

Behaviour changes to check at call sites:

| Was | Is | Watch for |
|---|---|---|
| `push`/`pop` **dropped** while busy | commands **queue** and run | Double-taps are two real commands — the second pop removes the screen *below*. Guard taps with `isTransitioning`. |
| `top` = current screen | `top` = **destination** | Anything reading `top` mid-transition now sees the incoming screen. |
| `push` with no stage silently no-op'd | completes `.discarded` | Code that polled for `stage != nil` should stash and flush in `didMove(toParent:)` instead. |
| covered screens: views stayed put | views **park off-screen** in the ledger | Don't touch a prop's transform while covered; the stage restores the recorded value. |

---

## Smells

Each of these was found in shipped code, most in more than one app.

1. **Asking the view hierarchy what the root is.** `top is LoginVC` reports the login gone the moment anything covers it; `children.contains { $0 is LoginVC }` reports it present for as long as it is anywhere in the stack. Both shipped as bugs, in opposite directions. Compare a stored intent.
2. **A private copy of the stage lookup.** Three apps independently wrote the `parent`-chain walk `Stageable.stage` already ships. If you're looping over `parent`, stop. (`stage` is on `Stageable`; a plain `UIViewController` nested inside a screen still needs the stage passed to it.)
3. **Polling for the stage to settle.** Ten hand-rolled `asyncAfter` variants across four apps, in five policies, four of them tuned to durations that are overridable anyway. Use a command completion or `stageDidSettle()`. Never sleep, never poll, never guess a constant.
4. **Recording an intent before the screen exists.** A failable factory after `installedRoot = desired` leaves the intent recorded with nothing installed — every later reconcile concludes the root already agrees, and the stage stays blank permanently.
5. **Asymmetric pre-install handling.** `viewIsAppearing` bailing without setting `didInstallRoot` strands the stage: it does not fire again. Set it in both branches.
6. **Two spellings of identity.** One app's reconcile read `Session.storage.loggedInUser` while its install path read `AppSession.hasPersistedIdentity`. Same value that day; that is exactly how two root decisions drift apart later.
7. **Blockers that discard instead of defer.** A launch-time takeover may veto the reconcile, but it must leave the need recorded and consume it when it clears — otherwise an identity change during the veto is swallowed.
8. **Treating `setRoot` as teardown.** It drops in-memory projections nothing else retains — it does not reclaim UserDefaults, statics, singletons, keychain or files, does not cancel in-flight `Task`s, and `removeFromParent` is not `deinit`. Correct teardown is one explicit pipeline; the root swap is a UI transition that happens to release some memory.
9. **Keeping a parallel copy of stage state.** `top`, `depth` and `contains` are exposed so you don't have to. A `currentTop` field assigned from a transition hook reports the incoming screen while the outgoing one is still on screen.
10. **Setting a transform on a prop view inside `willEnter()`.** Props park right after it returns, and the recorded value is the entrance *target* — a decorative pre-pose becomes the landing state. (The 2.2.0 engine silently discarded these; under 2.4 one shipped as a squished login screen.)

---

## Anatomy of a transition

```
┌─ EXIT PHASE ──────────────┐┌─ SEAM (instant) ─────────┐┌─ ENTER PHASE ─────────────┐
│ outgoing props park       ││ view swap · restore      ││ props return to their     │
│ chrome becoming absent    ││ parked · willEnter ·     ││ recorded values · chrome  │
│ rides along               ││ layout · re-park         ││ becoming present rides    │
└───────────────────────────┘└──────────────────────────┘└───────────────────────────┘
  willExit(exit) → didExit(exit)                           didEnter() → settle
```

A phase ends when its **last animator completes** — never on a timer. A phase with **no animators takes no time**: a propless→propless transition runs synchronously.

**A new screen is laid out during the exit, unseen.** Once the exit's last staggered prop has started (each starts from the main thread, so the wait keeps the stagger on time), a screen new to the stage is added hidden beneath everything at the stage's size and laid out. The render server is moving the exit by then, so the main thread is free, and the seam's layout finds nothing left to do. Laid out at the seam instead, a big screen held the stage blank between the phases (a textbook shelf: ~0.2 s on an A10). A covered screen coming back is not laid out early: its props are parked. The view is hidden, so no appearance calls move; SwiftUI content in it may see `onAppear` a little before the seam.

## The callback order

Fixed here, not decided by the implementation — `StageVCAppearanceTests` log-matches every scenario below against this table.

1. `stageWillBegin(.exit, from:to:)`
2. outgoing `willExit(exit)`; each also-leaving screen `willExit(.removed)`
3. outgoing `beginAppearanceTransition(false)` *(all appearance calls gated on the container itself being visible)*
4. exit phase runs · outgoing view removed · `endAppearanceTransition()`
5. outgoing `didExit(exit)`; each also-leaving screen released (**no appearance calls** — it was already covered); a `.removed` outgoing is un-parented · `stageDidEnd(.exit)`
6. **Seam:** add incoming view → reset transform → frame → raise chrome → restore parked views → `beginAppearanceTransition(true)` → `stageWillBegin(.enter)` → `willEnter()` → layout → read `props` → park them
7. enter phase runs — parked views to their recorded values, chrome becoming present alongside
8. `endAppearanceTransition()` · `didMove(toParent:)` if newly adopted · `didEnter()` · `stageDidEnd(.enter)`
9. completion(`.performed`) · drain the queue · `stageDidSettle()` once the queue is empty and nothing is in flight

| Scenario | Differences |
|---|---|
| First install | No outgoing: steps 1–5 skipped; chrome reconciles bare before the seam |
| Push | As written; outgoing takes `.covered` and stays parented |
| Pop / `replaceTop` | Outgoing takes `.removed`, un-parented at step 5 |
| `popToRoot` | Same, plus the also-leaving screens |
| `setRoot` naming the visible screen | A **strike**: the rest leave the stack (`willExit(.removed)` → released → `didExit(.removed)`), nothing on screen changes, no phases, no appearance calls; chrome reconciles bare |
| No plan (e.g. pop at root) | Completions fire (`.noop`/`.discarded`); nothing else — no settle |

| File | Purpose |
|---|---|
| `Navigator.swift` | The state machine — stack, queue, `Command` → `Plan`, `Exit`, `Outcome` |
| `StageVC.swift` | The container — pump, phases, parking ledger, chrome, appearance |
| `Stageable.swift` | The screen protocol, `stage` lookup, navigation conveniences |
| `Chrome.swift` | `Chrome`, `Phase`, `StageObserver` |
| `Prop.swift` | Declarative description of an animated view element |
