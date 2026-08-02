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

Direction props (`.top`, `.bottom`, `.left`, `.right`, and the corners) slide fully off their **superview**; `Prop(view, transform:)` expresses anything else. Off-screen travel is measured in the superview's space, so props inside inset containers, inner stages, and non-fullscreen windows all travel the correct distance.

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

Read state from the stage, never the view hierarchy: `top`, `depth`, `contains(_:)` — all describe the **destination** during a transition.

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

---

## The callback order

The full per-transition order — who is told what, when, including appearance forwarding, containment, and where chrome rides — is fixed by the A7 table in `docs/systems/frameworks/stageable-rebuild-plan.md` and enforced by `StageVCAppearanceTests`, which log-match every scenario against it.

| File | Purpose |
|---|---|
| `Navigator.swift` | The state machine — stack, queue, `Command` → `Plan`, `Exit`, `Outcome` |
| `StageVC.swift` | The container — pump, phases, parking ledger, chrome, appearance |
| `Stageable.swift` | The screen protocol, `stage` lookup, navigation conveniences |
| `Chrome.swift` | `Chrome`, `Phase`, `StageObserver` |
| `Prop.swift` | Declarative description of an animated view element |
